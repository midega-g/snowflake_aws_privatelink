# 01 Networking

Provisions the VPC, subnets, gateways, and route tables in the sandbox account (us-west-2).

## Resources Created

- VPC (10.0.0.0/16) with DNS hostnames and DNS support enabled
- 3 public subnets (/24, one per AZ: us-west-2a, 2b, 2c)
- 3 private subnets (/20, one per AZ)
- Internet Gateway
- NAT Gateway (single AZ for cost optimization in sandbox)
- Public and private route tables with associations

## Subnet Allocation

| Subnet | CIDR | Usable IPs |
|--------|------|-----------|
| Public us-west-2a | 10.0.1.0/24 | 251 |
| Public us-west-2b | 10.0.2.0/24 | 251 |
| Public us-west-2c | 10.0.3.0/24 | 251 |
| Private us-west-2a | 10.0.16.0/20 | 4,091 |
| Private us-west-2b | 10.0.32.0/20 | 4,091 |
| Private us-west-2c | 10.0.48.0/20 | 4,091 |

## Prerequisites

- AWS CLI authenticated (`export AWS_PROFILE=org_mgmt_epf`)
- Sandbox account provisioned (state at `sandbox/terraform.tfstate`)
- S3 state bucket accessible

## Apply

```bash
terraform init
terraform plan
terraform apply
```

## Auth Flow

```
org_mgmt_epf (management account) → assume_role → sandbox OrganizationAccountAccessRole
```

The provider uses the global STS endpoint to work around the af-south-1 → us-west-2
cross-region AssumeRole limitation (`sts_region` remains `us-east-1` for signing).

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
