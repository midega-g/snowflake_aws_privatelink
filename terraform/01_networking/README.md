# 01 Networking

Provisions the VPC, subnets, gateways, and route tables in the sandbox account (us-east-1).

## Resources Created

- VPC (10.0.0.0/16) with DNS hostnames and DNS support enabled
- 3 public subnets (one per AZ: us-east-1a, 1b, 1c)
- 3 private subnets (one per AZ)
- Internet Gateway
- NAT Gateway (single AZ for cost optimization in sandbox)
- Public and private route tables with associations

## Prerequisites

- `snowflake-privatelink-admin` IAM role assumed
- S3 state bucket accessible

## Apply

```bash
terraform init
terraform plan
terraform apply
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
