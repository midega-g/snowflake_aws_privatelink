# 01 Networking

Provisions the VPC, subnets, gateways, and route tables in the sandbox account (us-east-1).

## Resources Created

- VPC (10.0.0.0/16) with DNS hostnames and DNS support enabled
- 3 public subnets (/24, one per AZ: us-east-1a, 1b, 1c)
- 3 private subnets (/20, one per AZ)
- Internet Gateway
- NAT Gateway (single AZ for cost optimization in sandbox)
- Public and private route tables with associations

## Subnet Allocation

| Subnet | CIDR | Usable IPs |
|--------|------|-----------|
| Public us-east-1a | 10.0.1.0/24 | 251 |
| Public us-east-1b | 10.0.2.0/24 | 251 |
| Public us-east-1c | 10.0.3.0/24 | 251 |
| Private us-east-1a | 10.0.16.0/20 | 4,091 |
| Private us-east-1b | 10.0.32.0/20 | 4,091 |
| Private us-east-1c | 10.0.48.0/20 | 4,091 |

## Prerequisites

- AWS CLI authenticated (`export AWS_PROFILE=org_mgmt_pf`)
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
org_mgmt_pf (management account) → assume_role → sandbox OrganizationAccountAccessRole
```

The provider uses the global STS endpoint to work around the af-south-1 → us-east-1
cross-region AssumeRole limitation.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
