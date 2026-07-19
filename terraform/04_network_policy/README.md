# 04 Network Policy

Restricts Snowflake account access to PrivateLink traffic (VPC CIDR) and the
operator's IP only. All other public internet access is blocked.

## Resources Created (Snowflake-side only)

- Network rule: VPC CIDR (`10.0.0.0/16`) — PrivateLink traffic
- Network rule: Operator IP — debug/admin access from laptop
- Network policy: References both rules, blocks all else
- Account parameter: Activates the policy at account level

## Prerequisites

- `02_privatelink` applied and PrivateLink validated
- Snowflake credentials configured (`~/.snowflake/config`)
- AWS_PROFILE exported (for S3 backend state access)

## Apply

```bash
export AWS_PROFILE=org_mgmt_epf
terraform init
terraform apply -var="operator_ip=$(curl -s ifconfig.me)/32"
```

## Cost

$0.00 — network policies are a free Snowflake account setting.

## Rollback (if locked out)

```bash
# Option 1: Connect from EC2 inside VPC (always allowed by VPC CIDR rule)
ssh -i ../03_ec2_test/snowflake-privatelink-test-key.pem ec2-user@<linux_ip>
~/bin/snowsql -a qbb21532.us-west-2.privatelink -u SNOWLEARN \
  -q "ALTER ACCOUNT UNSET NETWORK_POLICY;"

# Option 2: Destroy the policy entirely
terraform destroy -var="operator_ip=$(curl -s ifconfig.me)/32"
```

## Demonstrating Enforcement

```bash
# 1. After apply — verify laptop access works (your IP allowed)
# 2. Remove your IP: terraform apply -var="operator_ip=0.0.0.0/32"
#    → Laptop is blocked from Snowsight
# 3. Restore: terraform apply -var="operator_ip=$(curl -s ifconfig.me)/32"
#    → Laptop access restored
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
