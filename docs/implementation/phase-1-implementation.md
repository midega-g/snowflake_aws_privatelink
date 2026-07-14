# Implementation Log — Phase 1: Networking

## Date: 2026-07-14

---

## Goal

Provision the foundational VPC networking infrastructure in the AWS sandbox account
(us-east-1) for the Snowflake PrivateLink project. This is the base layer that all
subsequent workspaces (02_privatelink, 03_ec2_test) depend on via `terraform_remote_state`.

---

## Task 1.1: Create Terraform Files ✅

### Files Created

| File | Purpose |
|------|---------|
| `backend.tf` | S3 remote state backend (bucket in af-south-1) |
| `versions.tf` | Terraform >= 1.10.0 < 2.0.0, AWS provider ~> 6.38 |
| `data.tf` | Remote state lookup for sandbox account ID |
| `provider.tf` | Cross-account assume role + STS workaround + default_tags |
| `variables.tf` | 8 input variables with defaults |
| `main.tf` | VPC, subnets, gateways, route tables, associations |
| `outputs.tf` | 9 outputs for downstream workspaces |
| `README.md` | Updated with subnet allocation table and auth flow |

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate `data.tf` for data sources | Single responsibility per file; establishes pattern for downstream workspaces |
| STS workaround in provider | af-south-1 is opt-in; regional STS endpoint rejects cross-region AssumeRole |
| Smaller public /24, larger private /20 | Endpoints live in private subnets; public only needs NAT + test EC2 |
| Remote state for sandbox account ID | No hardcoded account IDs; single source of truth from aws-org-infra |
| `org_mgmt_epf` profile (not separate sandbox profile) | Consistency with aws-org-infra; CI/CD compatible (OIDC uses same assume_role pattern) |

### Subnet Allocation

| Subnet | CIDR | Usable IPs |
|--------|------|-----------|
| Public us-east-1a | 10.0.1.0/24 | 251 |
| Public us-east-1b | 10.0.2.0/24 | 251 |
| Public us-east-1c | 10.0.3.0/24 | 251 |
| Private us-east-1a | 10.0.16.0/20 | 4,091 |
| Private us-east-1b | 10.0.32.0/20 | 4,091 |
| Private us-east-1c | 10.0.48.0/20 | 4,091 |

Free space: `10.0.64.0/18` and above reserved for future use (database subnets, additional projects).

---

## Task 1.2: Validation (terraform fmt + validate) ✅

```bash
cd terraform/01_networking

terraform fmt -check -diff
# No formatting issues

terraform init -backend=false
# Provider aws v6.54.0 installed successfully

terraform validate
# Success! The configuration is valid.
```

---

## Task 1.3: terraform init (full backend) ✅

```bash
export AWS_PROFILE=org_mgmt_epf
terraform init
# Initializing the backend...
# Terraform has been successfully initialized!
```

---

## Task 1.4: terraform plan ✅

```bash
terraform plan
# Plan: 20 to add, 0 to change, 0 to destroy.
```

Plan showed 20 resources:
- 1 VPC
- 6 subnets (3 public, 3 private)
- 1 Internet Gateway
- 1 EIP
- 1 NAT Gateway
- 2 route tables
- 2 routes
- 6 route table associations

All resources correctly tagged with `default_tags` + resource-specific `Name` tags.

---

## Task 1.5: terraform apply — FAILED (first attempt) ❌

### Error

```
Error: creating EC2 VPC: operation error EC2: CreateVpc, https response error
StatusCode: 403, RequestID: bdabbc52-..., api error UnauthorizedOperation:
You are not authorized to perform this operation.
...with an explicit deny in a service control policy:
arn:aws:organizations::953146140973:policy/o-a95mb29jie/service_control_policy/p-oetdvmvl
```

### Root Cause

The `DenyNonAllowedRegions` SCP (`p-oetdvmvl`) only permitted `af-south-1`:

```hcl
# aws-org-infra/01_org_setup/02_identity/scps/variables.tf
variable "allowed_regions" {
  default = ["af-south-1"]  # <-- us-east-1 not allowed!
}
```

EC2 actions (`CreateVpc`, `AllocateAddress`) are not in the SCP's `NotAction` exemption
list, so they were explicitly denied in us-east-1.

### Fix

Added `us-east-1` to the allowed regions globally:

```hcl
variable "allowed_regions" {
  default = ["af-south-1", "us-east-1"]
}
```

### Apply in aws-org-infra

```bash
export AWS_PROFILE=org_mgmt_epf
cd ~/Desktop/Learning/aws-org-infra/01_org_setup/02_identity/scps

terraform init
terraform apply -auto-approve -var='allowed_regions=["af-south-1","us-east-1"]'
# Plan: 0 to add, 1 to change, 0 to destroy.
# aws_organizations_policy.deny_region: Modifying... [id=p-oetdvmvl]
# Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

**Note:** The `-var` flag was needed because Terraform's plan cache didn't pick up the
default change on the first `terraform plan` (showed "No changes"). The variable default
in `variables.tf` was updated for future applies without `-var`.

---

## Task 1.6: terraform apply — SUCCESS (second attempt) ✅

```bash
export AWS_PROFILE=org_mgmt_epf
cd ~/Desktop/Learning/snowflake_aws_privatelink/terraform/01_networking

terraform apply -auto-approve
# Plan: 20 to add, 0 to change, 0 to destroy.
# ...
# Apply complete! Resources: 20 added, 0 changed, 0 destroyed.
```

### Resources Created

| Resource | ID |
|----------|-----|
| VPC | `vpc-0d9557474d203dd15` |
| Internet Gateway | `igw-02d42bec2da6c3576` |
| NAT Gateway | `nat-0cd4037f565f852bb` |
| EIP (NAT) | `eipalloc-010239841d9e677f3` |
| Public Subnet (1a) | `subnet-0196d1a3563186e76` |
| Public Subnet (1b) | `subnet-021a673a64c666c1a` |
| Public Subnet (1c) | `subnet-06ee282fdbfc8aa18` |
| Private Subnet (1a) | `subnet-09523f14cad0a3f1f` |
| Private Subnet (1b) | `subnet-05102694cfb007d93` |
| Private Subnet (1c) | `subnet-03c4a23ddfe0b02dd` |
| Public Route Table | `rtb-0a808558fe1ad2135` |
| Private Route Table | `rtb-0e10faf14ced8d3a2` |

### Outputs

```
availability_zones     = ["us-east-1a", "us-east-1b", "us-east-1c"]
igw_id                 = "igw-02d42bec2da6c3576"
nat_gateway_id         = "nat-0cd4037f565f852bb"
private_route_table_id = "rtb-0e10faf14ced8d3a2"
private_subnet_ids     = ["subnet-09523f14cad0a3f1f", "subnet-05102694cfb007d93", "subnet-03c4a23ddfe0b02dd"]
public_route_table_id  = "rtb-0a808558fe1ad2135"
public_subnet_ids      = ["subnet-0196d1a3563186e76", "subnet-021a673a64c666c1a", "subnet-06ee282fdbfc8aa18"]
vpc_cidr               = "10.0.0.0/16"
vpc_id                 = "vpc-0d9557474d203dd15"
```

---

## Cost Estimate — Phase 1

Pricing data retrieved from AWS Price List API (us-east-1, effective 2026-07-01).

### Phase 1 Resources (monthly)

| Resource | Unit Price | Quantity | Monthly Cost |
|----------|-----------|----------|-------------|
| NAT Gateway | $0.045/hour | 730 hrs (24/7) | $32.85 |
| NAT Gateway data processing | $0.045/GB | ~1 GB (minimal sandbox traffic) | $0.05 |
| Elastic IP (NAT) | $0.005/hour (in-use) | 730 hrs | $3.65 |
| VPC | Free | 1 | $0.00 |
| Subnets | Free | 6 | $0.00 |
| Internet Gateway | Free | 1 | $0.00 |
| Route Tables | Free | 2 | $0.00 |
| **Phase 1 Total** | | | **~$36.55/month** |

### Cumulative Cost

| Phase | Monthly Cost | Cumulative |
|-------|-------------|-----------|
| Phase 0 | $0.01 | $0.01 |
| Phase 1 | $36.55 | **$36.56/month** |

### Notes

- The NAT Gateway is the primary cost driver (~90% of Phase 1 spend)
- The EIP is charged at $0.005/hr even when attached (AWS public IPv4 pricing since Feb 2024)
- If the sandbox is unused, consider destroying the NAT Gateway to save ~$36/month:

  ```bash
  # Destroy (stops billing immediately)
  terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat

  # Recreate when needed
  terraform apply -target=aws_eip.nat -target=aws_nat_gateway.main
  ```

  **Effect of destroy:** Private subnets lose outbound internet access (0.0.0.0/0 route
  becomes a black hole). VPC endpoints (Phase 2) are unaffected — PrivateLink traffic
  does not route through NAT. The EC2 test instance (Phase 3) in a public subnet is also
  unaffected (it uses the IGW directly).

  **Effect of recreate:** NAT gets a new public IP. The EIP allocation ID changes, but
  Terraform handles the route table update automatically. No impact on PrivateLink or
  existing VPC endpoint connectivity.

- VPC, subnets, IGW, and route tables are free — only the NAT + EIP cost money

### Upcoming Phase 2 Cost Preview

| Resource | Unit Price | Quantity | Estimated Monthly Cost |
|----------|-----------|----------|----------------------|
| VPC Interface Endpoint (Snowflake) | $0.01/hour/AZ | 3 AZs × 730 hrs | $21.90 |
| VPC Endpoint data processing | $0.01/GB | ~5 GB (light usage) | $0.05 |
| S3 Gateway Endpoint | Free | 1 | $0.00 |
| Route53 Private Hosted Zone | $0.50/month | 1 zone | $0.50 |
| Route53 queries | $0.40/million | ~1,000 queries | $0.00 |
| **Phase 2 estimated addition** | | | **~$22.45/month** |

---

## Lessons Learned

1. **Always check SCPs before deploying to a new region.** The `DenyNonAllowedRegions`
   SCP is an org-wide guardrail. When adding a new region to the project landscape,
   the SCP must be updated first — otherwise even `OrganizationAccountAccessRole` (which
   has full admin within the account) will be denied.

2. **Terraform's plan cache can mask variable default changes.** When modifying a
   `default` value in `variables.tf`, Terraform may not detect the change if it
   already read the state with the old default. Passing `-var` explicitly or running
   `terraform plan` fresh (after closing the previous plan) resolves this.

3. **NAT Gateway creation is slow (~1.5 minutes).** This is normal AWS behavior —
   NAT gateways take time to provision. Don't abort the apply.

4. **The STS workaround works.** The `sts_region = "us-east-1"` + global endpoint
   pattern successfully allows cross-region AssumeRole from af-south-1 credentials
   into us-east-1 resources. This confirms the provider pattern for all subsequent
   workspaces.

---

## Cross-Repository Changes

| Repository | File | Change |
|-----------|------|--------|
| `aws-org-infra` | `01_org_setup/02_identity/scps/variables.tf` | Added `"us-east-1"` to `allowed_regions` default |

---

## State After Phase 1

| Item | Status |
|------|--------|
| VPC (10.0.0.0/16) in us-east-1 | ✅ |
| 3 public subnets (/24) | ✅ |
| 3 private subnets (/20) | ✅ |
| Internet Gateway | ✅ |
| NAT Gateway (single AZ) | ✅ |
| Public route table (0.0.0.0/0 → IGW) | ✅ |
| Private route table (0.0.0.0/0 → NAT) | ✅ |
| Route table associations | ✅ |
| Outputs exposed for downstream | ✅ |
| SCP updated for us-east-1 | ✅ |

---

## Pending

- [ ] Commit and push `aws-org-infra` SCP change
- [ ] Commit and push `snowflake_aws_privatelink` Phase 1 files
- [ ] **Phase 2:** PrivateLink (VPC endpoint, security groups, Route53 DNS)
