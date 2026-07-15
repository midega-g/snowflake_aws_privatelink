# Region Migration: us-east-1 → us-west-2

## Date: 2026-07-15

---

## Background

The project was originally designed and deployed targeting **us-east-1** based on an
assumption about the Snowflake account region. After Phase 1 networking was applied
(20 resources created in us-east-1), it was identified that the Snowflake Business
Critical account is actually in **us-west-2**.

AWS PrivateLink requires the VPC and Snowflake account to be in the same region —
there is no cross-region workaround without a custom endpoint service (out of scope).
The entire networking layer had to be destroyed and recreated in us-west-2.

---

## Impact Assessment

### What had to change

| Category | Scope |
|----------|-------|
| Live infrastructure (Phase 1) | Destroy 20 resources in us-east-1, recreate in us-west-2 |
| SCP (aws-org-infra) | Add `us-west-2` to allowed regions |
| Terraform code | Region defaults, AZ names, STS signing region |
| Spec files (4 files) | All region references in requirements, design, tasks, checklist |
| Implementation docs | Phase 1 log region references |
| Scripts | Default region in `test-connectivity.sh` |
| README | Architecture diagram region labels |

### What stayed the same

- VPC CIDR (10.0.0.0/16), subnet sizing, route table structure
- Backend config (state bucket in af-south-1, cross-region access works)
- IAM role in management account (region-agnostic)
- Provider assume_role pattern
- All resource naming and tagging
- `us-east-1` retained in SCP `allowed_regions` (for org-level services)

---

## Step 1: Destroy Existing Infrastructure

```bash
export AWS_PROFILE=org_mgmt_epf
cd ~/Desktop/Learning/snowflake_aws_privatelink/terraform/01_networking

terraform destroy -auto-approve
# Destroy complete! Resources: 20 destroyed.
```

Resources destroyed:
- VPC, 6 subnets, IGW, NAT Gateway, EIP
- 2 route tables, 2 routes, 6 route table associations

---

## Step 2: Update SCP (aws-org-infra)

### Root Cause: `terraform.tfvars` Override

The `variables.tf` had been updated previously to include `us-east-1`:

```hcl
# variables.tf (default was updated but ineffective)
variable "allowed_regions" {
  default = ["af-south-1", "us-east-1"]
}
```

But the **`terraform.tfvars`** was still overriding it:

```hcl
# terraform.tfvars — THIS TAKES PRECEDENCE
allowed_regions = ["af-south-1"]
```

Previous applies used `-var` flag which worked in-session but didn't persist.
The SCP in AWS only had `af-south-1` allowed.

### Fix

Updated both files to include all 3 regions:

**`01_org_setup/02_identity/scps/terraform.tfvars`:**

```hcl
aws_region      = "af-south-1"
state_bucket    = "ecommerce-tf-state-mgmt"
allowed_regions = ["af-south-1", "us-east-1", "us-west-2"]
```

**`01_org_setup/02_identity/scps/variables.tf`:**

```hcl
variable "allowed_regions" {
  description = "List of AWS regions member accounts are permitted to use."
  type        = list(string)
  default     = ["af-south-1", "us-east-1", "us-west-2"]
}
```

### Apply

```bash
cd ~/Desktop/Learning/aws-org-infra/01_org_setup/02_identity/scps

AWS_PROFILE=org_mgmt_epf terraform apply -auto-approve
# aws_organizations_policy.deny_region: Modifying... [id=p-oetdvmvl]
# aws_organizations_policy.deny_region: Modifications complete after 1s
# Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

### Verification

```bash
terraform show | grep -A5 "RequestedRegion"
# "aws:RequestedRegion" = [
#     "af-south-1",
#     "us-east-1",
#     "us-west-2",
# ]
```

---

## Step 3: Update Terraform Code

### `terraform/01_networking/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-west-2"          # Changed from us-east-1
}

variable "availability_zones" {
  description = "List of availability zones for subnet placement."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]  # Changed from us-east-1a/b/c
}
```

### `terraform/01_networking/provider.tf`

```hcl
provider "aws" {
  region = var.aws_region   # Now resolves to us-west-2

  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.sandbox.outputs.sandbox_account_id}:role/OrganizationAccountAccessRole"
  }

  # Cross-region STS workaround (af-south-1 → us-east-1)
  # sts_region must be us-east-1 because we use the global STS endpoint
  # (sts.amazonaws.com), which requires us-east-1 for credential signing.
  sts_region = "us-east-1"

  endpoints {
    sts = "https://sts.amazonaws.com"
  }

  default_tags { ... }
}
```

### `terraform/01_networking/main.tf`

Only the header comment changed (`us-east-1` → `us-west-2`). The actual resource
definitions are region-agnostic — they reference `var.availability_zones` and
`var.aws_region` rather than hardcoded strings.

---

## Step 4: Update Spec Files

All 4 spec files under `.kiro/specs/` updated:

| File | Changes |
|------|---------|
| `01-requirements.md` | FR-02 VPC region, FR-04 S3 service name, FR-05 CNAME records, Section 4 constraint, Section 5 assumptions |
| `02-design.md` | Architecture diagram (AWS/Snowflake/AZ labels), provider config block, checklist table |
| `03-tasks.md` | Task 1.1 AZ names, Task 1.2 NAT AZ, Task 2.4 S3 service name, Task 2.5 CNAMEs, Task 3.3 subnet, Task 4.1 nslookup |
| `04-checklist.md` | Items #4 (AWS Region) and #5 (Snowflake Region → `AWS_US_WEST_2`) |

---

## Step 5: Update Scripts and Documentation

| File | Change |
|------|--------|
| `scripts/test-connectivity.sh` | Default `REGION` from `us-east-1` to `us-west-2` |
| `README.md` | Architecture diagram subgraph labels, prerequisites region |
| `docs/implementation/phase-1-implementation.md` | AZ names, subnet table, STS workaround lesson, SCP cross-repo change |

---

## Step 6: Apply Networking in us-west-2

### First Attempt — STS Signing Error

```
Error: operation error STS: AssumeRole, ...
api error SignatureDoesNotMatch: Credential should be scoped to a valid region.
```

**Cause:** Initially set `sts_region = "us-west-2"` thinking it should match the
target region. The global STS endpoint (`sts.amazonaws.com`) requires credentials
scoped to `us-east-1` regardless of target. Fixed by keeping `sts_region = "us-east-1"`.

### Second Attempt — SCP Deny

```
Error: creating EC2 VPC: ... api error UnauthorizedOperation: ...
explicit deny in a service control policy
```

**Cause:** Not propagation delay — the `terraform.tfvars` override meant the SCP
never actually had `us-west-2` until Step 2 was properly resolved.

### Successful Apply

```bash
export AWS_PROFILE=org_mgmt_epf
cd ~/Desktop/Learning/snowflake_aws_privatelink/terraform/01_networking

terraform apply -auto-approve
# Apply complete! Resources: 20 added, 0 changed, 0 destroyed.
```

### Outputs

```
availability_zones     = ["us-west-2a", "us-west-2b", "us-west-2c"]
vpc_cidr               = "10.0.0.0/16"
```

All resource IDs available via `terraform output` — VPC, subnets, gateways, and
route tables created successfully in us-west-2.

---

## Lessons Learned

1. **`terraform.tfvars` always wins over variable defaults.** If you update
   `variables.tf` but a `terraform.tfvars` file exists with the same key, the
   tfvars value takes precedence. The `-var` flag overrides both but only for
   that single run — it doesn't persist. Always check for tfvars when a variable
   default change appears to have no effect.

2. **The global STS endpoint requires `us-east-1` for signing.** When using
   `endpoints { sts = "https://sts.amazonaws.com" }`, set `sts_region = "us-east-1"`
   regardless of the target region. The global endpoint lives in us-east-1; the
   target region is determined by the `region` attribute and `assume_role` block.

3. **AWS networking resources cannot be moved between regions.** VPCs, subnets,
   gateways, and route tables are regional. A region change requires full destroy
   and recreate. Terraform state tracks the old region — after destroy, a fresh
   `terraform apply` creates new resources in the updated region.

4. **SCP changes: check the actual applied state, not just the code.** Use
   `terraform show` to verify what's actually deployed. Don't blame propagation
   delay before confirming the policy content is correct.

5. **Keep `terraform.tfvars` and `variables.tf` defaults in sync.** If both exist,
   one of them becomes the source of confusion. Convention: use `terraform.tfvars`
   as the single source of truth for environment-specific values; use `variables.tf`
   defaults only as documentation of what's expected.

---

## Cross-Repository Changes

| Repository | File | Change |
|-----------|------|--------|
| `aws-org-infra` | `01_org_setup/02_identity/scps/variables.tf` | `allowed_regions` default → `["af-south-1", "us-east-1", "us-west-2"]` |
| `aws-org-infra` | `01_org_setup/02_identity/scps/terraform.tfvars` | `allowed_regions` → `["af-south-1", "us-east-1", "us-west-2"]` |

---

## Final State

| Item | Status |
|------|--------|
| Old us-east-1 infrastructure | Destroyed |
| SCP allows us-west-2 | ✅ |
| VPC (10.0.0.0/16) in us-west-2 | ✅ (`terraform output vpc_id`) |
| 3 public subnets (us-west-2a/b/c) | ✅ (`terraform output public_subnet_ids`) |
| 3 private subnets (us-west-2a/b/c) | ✅ (`terraform output private_subnet_ids`) |
| Internet Gateway | ✅ (`terraform output igw_id`) |
| NAT Gateway (single AZ) | ✅ (`terraform output nat_gateway_id`) |
| Route tables + associations | ✅ |
| All specs/docs/scripts updated | ✅ |

---

## Pending

- [x] Commit and push `aws-org-infra` SCP changes
- [x] Commit and push `snowflake_aws_privatelink` region migration
- [ ] **Phase 2:** PrivateLink (VPC endpoint, security groups, Route53 DNS) — now targeting us-west-2
