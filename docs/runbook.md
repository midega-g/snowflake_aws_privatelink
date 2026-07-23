# Runbook — Snowflake AWS PrivateLink

Operational guide for day-to-day management of the PrivateLink infrastructure.

---

## Prerequisites

```bash
export AWS_PROFILE=org_mgmt_epf
```

All Terraform commands require this profile (management account credentials that
assume into sandbox via `OrganizationAccountAccessRole`).

---

## Common Operations

### Update Operator IP (when your IP changes)

```bash
cd terraform/04_network_policy
terraform apply -var='operator_ip=["<new_ip>/32"]'
```

If you have multiple exit IPs (e.g., browser extension routes through a proxy):

```bash
terraform apply -var='operator_ip=["<ip_1>/32","<ip_2>/32"]'
```

To find your IPs:
- CLI: `curl -s ifconfig.me`
- Browser: check Snowflake's error message (shows the IP it sees)

---

### Re-test Connectivity (spin up EC2s)

```bash
cd terraform/03_ec2_test
terraform apply -var="operator_ip=$(curl -s ifconfig.me)/32"
```

This creates both Linux (SSH) and Windows (RDP) instances with all tools pre-installed
via user_data. After testing:

```bash
terraform destroy -var="operator_ip=$(curl -s ifconfig.me)/32"
```

---

### Recover from Network Policy Lockout

If you're blocked from Snowflake (policy doesn't include your IP):

```bash
# 1. Spin up test EC2 (VPC CIDR is always allowed)
cd terraform/03_ec2_test
terraform apply -var="operator_ip=$(curl -s ifconfig.me)/32"

# 2. SSH in and unset the policy
ssh -i ./snowflake-privatelink-test-key.pem ec2-user@$(terraform output -raw public_ip)

# Inside EC2:
SNOWSQL_PWD='<password>' ~/bin/snowsql \
  -a qbb21532.us-west-2.privatelink -u SNOWLEARN \
  -o friendly=false \
  -q "USE ROLE ACCOUNTADMIN; ALTER ACCOUNT UNSET NETWORK_POLICY;"
```

Or destroy the policy entirely:

```bash
cd terraform/04_network_policy
# This will fail if Terraform itself is blocked — use the EC2 method above first
terraform destroy -var='operator_ip=["0.0.0.0/32"]'
```

---

### Destroy NAT Gateway (save ~$36/month when idle)

The NAT Gateway is the biggest cost driver. PrivateLink does NOT use it.

```bash
cd terraform/01_networking
terraform destroy \
  -target=aws_nat_gateway.main \
  -target=aws_eip.nat \
  -target=aws_route.private_nat
```

**Effect:** Private subnets lose outbound internet (0.0.0.0/0 becomes a black hole).
VPC endpoints and PrivateLink are unaffected.

**Recreate when needed:**

```bash
terraform apply
```

---

### Verify PrivateLink Authorization Status

```bash
AWS_PROFILE=org_mgmt_epf ./scripts/verify-privatelink.sh
# Copy the SQL output → run in Snowflake
# Expected: "Account is authorized for PrivateLink."
```

Or query authorized endpoints directly in Snowflake:

```sql
SELECT
    REPLACE(value:endpointId, '"') AS endpoint_id,
    REPLACE(value:endpointIdType, '"') AS endpoint_type
FROM TABLE(FLATTEN(
    input => PARSE_JSON(SYSTEM$GET_PRIVATELINK_AUTHORIZED_ENDPOINTS())
));
```

---

### Revoke PrivateLink (full teardown)

**Order matters — reverse of setup:**

```bash
# 1. Remove network policy
cd terraform/04_network_policy
terraform destroy -var='operator_ip=["0.0.0.0/32"]'

# 2. Destroy PrivateLink infrastructure
cd ../02_privatelink
terraform destroy

# 3. Revoke Snowflake authorization
cd ../..
AWS_PROFILE=org_mgmt_epf ./scripts/revoke-privatelink.sh
# Copy SQL → run in Snowflake

# 4. Destroy networking (optional — may be used by other projects)
cd terraform/01_networking
terraform destroy
```

---

## Workspace Reference

| Workspace | Path | State Key | Depends On |
|-----------|------|-----------|-----------|
| Networking | `terraform/01_networking` | `projects/snowflake-privatelink/networking/terraform.tfstate` | None |
| PrivateLink | `terraform/02_privatelink` | `projects/snowflake-privatelink/privatelink/terraform.tfstate` | 01_networking |
| EC2 Test | `terraform/03_ec2_test` | `projects/snowflake-privatelink/ec2-test/terraform.tfstate` | 01_networking, 02_privatelink |
| Network Policy | `terraform/04_network_policy` | `projects/snowflake-privatelink/network-policy/terraform.tfstate` | 02_privatelink validated |

---

## Authentication

| System | Method | Location |
|--------|--------|----------|
| AWS | CLI profile | `~/.aws/config` (profile: `org_mgmt_epf`) |
| Snowflake (Terraform) | Config file | `~/.snowflake/config` (profile: `snowflake-privatelink-profile`) |
| Snowflake (SnowSQL) | Password prompt or `SNOWSQL_PWD` env var | Runtime |
| EC2 SSH | Key file | `terraform/03_ec2_test/snowflake-privatelink-test-key.pem` |
| EC2 RDP | Decrypted password | `terraform output -raw windows_admin_password \| base64 -d \| openssl pkeyutl -decrypt -inkey ./snowflake-privatelink-test-key.pem` |
