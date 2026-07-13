# 04 Network Policy

Snowflake network policy that restricts access to the VPC CIDR only, blocking all public internet access.

## Resources Created

- Snowflake network policy (allowed IPs: VPC CIDR)
- Account-level network policy activation

## Prerequisites

- `02_privatelink` applied and connectivity validated via `03_ec2_test`
- **WARNING:** Only apply AFTER confirming PrivateLink works. Applying prematurely will lock you out of Snowflake.

## Apply

```bash
terraform init
terraform plan
terraform apply
```

## Rollback

If locked out:
1. Connect from within the allowed CIDR and run: `ALTER ACCOUNT UNSET NETWORK_POLICY;`
2. Or contact Snowflake Support to temporarily disable the policy

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
