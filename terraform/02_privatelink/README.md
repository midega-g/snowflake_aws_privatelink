# 02 PrivateLink

Creates the Snowflake PrivateLink infrastructure in the sandbox account, including
the authorization mechanism, VPC endpoints, security groups, and DNS.

## Resources Created

- **Auth:** IAM user (`snowflake-privatelink-auth`) with only `sts:GetFederationToken`
- **Security Group:** Inbound port 443 (HTTPS) + port 80 (OCSP) from VPC CIDR
- **VPC Endpoint (Interface):** Snowflake PrivateLink — across all 3 AZs
- **VPC Endpoint (Gateway):** S3 internal stage traffic
- **Route53 Private Hosted Zone:** `privatelink.snowflakecomputing.com`
- **CNAME Records:** Account URL and OCSP URL → VPCE regional DNS

## Prerequisites

- `01_networking` applied
- Snowflake Business Critical account in us-west-2 with ACCOUNTADMIN access
- Snowflake provider authentication configured (key-pair or SSO)

## Apply

```bash
export AWS_PROFILE=org_mgmt_epf
terraform init
terraform apply -var="snowflake_organization=<ORG>" -var="snowflake_account=<ACCT>"
```

## Snowflake Authorization (one-time, after first apply)

The auth user is created as part of this workspace. After `terraform apply`:

```bash
# 1. Generate federation token and get the SQL
./scripts/authorize-privatelink.sh

# 2. Run the SQL output in Snowflake as ACCOUNTADMIN

# 3. Verify
./scripts/verify-privatelink.sh
```

## File Layout

| File | Purpose |
|------|---------|
| `auth.tf` | Ephemeral IAM user for federation token generation |
| `main.tf` | Security group, Snowflake VPCE, S3 gateway endpoint |
| `dns.tf` | Route53 private hosted zone + CNAME records |
| `data.tf` | Remote state lookups (sandbox account, networking) |
| `provider.tf` | AWS (assume role) + Snowflake (ACCOUNTADMIN) providers |
| `variables.tf` | Region, project name, Snowflake org/account |
| `outputs.tf` | Auth creds, VPCE ID/DNS, security group, hosted zone |

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
