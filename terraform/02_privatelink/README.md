# 02 PrivateLink

Creates the Snowflake VPC Interface Endpoint, S3 Gateway Endpoint, security groups, and Route53 private hosted zones.

## Resources Created

- VPC Endpoint (Interface) for Snowflake PrivateLink — across all 3 AZs
- VPC Endpoint (Gateway) for S3 internal stage traffic
- Security group: inbound port 443 (HTTPS) + port 80 (OCSP) from VPC CIDR
- Route53 private hosted zone: `privatelink.snowflakecomputing.com`
- CNAME records for account URL and OCSP URL

## Prerequisites

- `01_networking` applied
- Snowflake PrivateLink authorized (run `./scripts/authorize-privatelink.sh` first)
- Snowflake provider configured with ACCOUNTADMIN access

## Apply

```bash
terraform init
terraform plan
terraform apply
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
