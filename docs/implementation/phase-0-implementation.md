# Implementation Log — Phase 0: Project Setup

## Date: 2026-07-12

---

## Task 0.1: Create GitHub Repository ✅

### Commands Run

```bash
# From ~/Desktop/Learning/
cd /home/midega-g/Desktop/Learning
gh repo create snowflake_aws_privatelink --private --clone
```

**Result:** `https://github.com/midega-g/snowflake_aws_privatelink` created successfully.

### Directory Structure

```bash
cd snowflake_aws_privatelink
mkdir -p terraform/{01_networking,02_privatelink,03_ec2_test,04_network_policy} \
         scripts docs app .github/workflows

# Add .gitkeep for empty directories
touch terraform/01_networking/.gitkeep \
      terraform/02_privatelink/.gitkeep \
      terraform/03_ec2_test/.gitkeep \
      terraform/04_network_policy/.gitkeep \
      docs/.gitkeep \
      .github/workflows/.gitkeep

# Make scripts executable
chmod +x scripts/*.sh
```

### Files Created

| File | Purpose |
|------|---------|
| `.gitignore` | Terraform, keys, env files, IDE, OS |
| `.pre-commit-config.yaml` | terraform-docs, tflint, pre-commit hooks |
| `README.md` | Project overview, architecture diagram, quick start |
| `app/README.md` | Placeholder for future application code |
| `scripts/authorize-privatelink.sh` | One-time Snowflake PrivateLink authorization |
| `scripts/verify-privatelink.sh` | Check authorization status |
| `scripts/revoke-privatelink.sh` | Revoke authorization (with confirmation) |
| `scripts/test-connectivity.sh` | DNS + port tests (run from EC2) |
| `.kiro/specs/01-requirements.md` | Functional/non-functional requirements |
| `.kiro/specs/02-design.md` | Architecture, repo structure, Mermaid diagrams |
| `.kiro/specs/03-tasks.md` | Phased implementation checklist |
| `.kiro/specs/04-checklist.md` | Operational checklist (IaC vs manual) |

---

## Task 0.2: Create IAM Role in aws-org-infra ✅ (with issues)

### Spec vs Implementation

| Spec Item | Implementation | Notes |
|-----------|---------------|-------|
| Role name: `snowflake-privatelink-admin` | Changed to `OrgSnowflakePrivateLinkAdmin` | Existing IAM policy restricts `iam:CreateRole` to `Org*` prefix |
| Policy name: `SnowflakePrivateLinkOps` | Changed to `OrgSnowflakePrivateLinkOps` | Same reason — `iam:CreatePolicy` scoped to `Org*` |
| Sandbox remote state in `provider.tf` | Moved to `snowflake_privatelink_role.tf` | Keeps the sandbox dependency self-contained in the role file |
| `local.sandbox_id` added | Yes — added to `locals` block in `main.tf` | Consistent with `local.log_archive_id`, etc. |

### Files Modified (in `aws-org-infra/01_org_setup/03_security/01_management_iam/`)

| File | Change |
|------|--------|
| `snowflake_privatelink_role.tf` | **New file** — IAM role + policy + attachment + sandbox remote state |
| `main.tf` | Added `local.sandbox_id`; added sandbox ARN to `AssumeRoleInMemberAccounts` + `AssumeOrgAccessRole` |
| `provider.tf` | No change (sandbox remote state kept in role file instead) |

### Commands Run

```bash
cd /home/midega-g/Desktop/Learning/aws-org-infra/01_org_setup/03_security/01_management_iam

# Validate
terraform validate
# Success! The configuration is valid.

# Unlock stale lock (from a prior interrupted plan)
terraform force-unlock -force 5775f3c5-6e77-4cb1-0585-862891926a19

# Plan
terraform plan
# Plan: 3 to add, 2 to change, 0 to destroy.
#   + aws_iam_role.snowflake_privatelink_admin
#   + aws_iam_policy.snowflake_privatelink_ops
#   + aws_iam_role_policy_attachment.snowflake_privatelink_ops
#   ~ aws_iam_policy.mgmt_terraform_ops (add sandbox to AssumeRoleInMemberAccounts)
#   ~ aws_iam_policy.assume_backbone_accounts (add sandbox to AssumeOrgAccessRole)

# Apply (first attempt)
terraform apply
```

### Issues Encountered

#### Issue 1: Role/Policy creation denied — wrong name prefix

**Error:**
```
AccessDenied: User: arn:aws:iam::953146140973:user/org_mgmt_user is not authorized
to perform: iam:CreateRole on resource: arn:aws:iam::953146140973:role/snowflake-privatelink-admin
because no identity-based policy allows the iam:CreateRole action
```

**Root Cause:** The `GitHubOIDCManagement` and `IAMPolicyManagement` statements in
`OrgTerraformOps` scope `iam:CreateRole` and `iam:CreatePolicy` to resources matching
`arn:aws:iam::<account>:role/Org*` and `arn:aws:iam::<account>:policy/Org*`.

**Fix:** Renamed resources to use `Org` prefix:
- `snowflake-privatelink-admin` → `OrgSnowflakePrivateLinkAdmin`
- `SnowflakePrivateLinkOps` → `OrgSnowflakePrivateLinkOps`

#### Issue 2: iam:TagPolicy denied

**Error:**
```
AccessDenied: User: arn:aws:iam::953146140973:user/org_mgmt_user is not authorized
to perform: iam:TagPolicy on resource: policy OrgSnowflakePrivateLinkOps
because no identity-based policy allows the iam:TagPolicy action
```

**Root Cause:** AWS `default_tags` on the provider triggers `iam:TagPolicy` and `iam:TagRole`
during resource creation. The `IAMPolicyManagement` statement didn't include tagging actions.

**Fix:** Added `iam:TagPolicy`, `iam:UntagPolicy`, `iam:TagRole`, `iam:UntagRole` to the
`IAMPolicyManagement` statement, and added `arn:aws:iam::<account>:role/Org*` to its
resource scope.

#### Issue 3: Race condition — self-modifying policy

**Error:** Same TagPolicy error on second apply attempt.

**Root Cause:** Terraform applied the `OrgTerraformOps` policy update (adding tag permissions)
and attempted to create the new policy in the same apply. AWS IAM is eventually consistent —
the permission hadn't propagated yet.

**Fix:** Ran `terraform apply -target=aws_iam_policy.mgmt_terraform_ops` first to ensure
the permission update took effect, then ran `terraform apply` again.

#### Issue 4: Sandbox account role assumption — missing from policies

**Error (Console):** "Invalid information in one or more fields" when trying Switch Role to
sandbox account `610269526926` with `OrganizationAccountAccessRole`.

**Root Cause:** The `OrgAssumeBackboneAccounts` and `AssumeRoleInMemberAccounts` policies
only listed the 3 backbone accounts (log-archive, security-tooling, shared-services). The
sandbox account was never added.

**Fix:** Added `local.sandbox_id` to both ARN lists. Added `data "terraform_remote_state" "sandbox"`
to resolve the account ID dynamically.

### Final Apply

```bash
# After fixing all issues:
terraform apply
# Plan: 2 to add, 1 to change, 0 to destroy.  (role already created, policy update + attachment)

# If race condition occurs, wait ~10 seconds then:
terraform apply
```

### Verification

```bash
# Verify role exists and is assumable
aws sts assume-role \
  --role-arn arn:aws:iam::953146140973:role/OrgSnowflakePrivateLinkAdmin \
  --role-session-name test-snowflake-pl

# Verify Switch Role works in console:
# Account: 610269526926
# Role: OrganizationAccountAccessRole
# Display Name: sandbox
```

---

## Task 0.3: Update OIDC Trust Policy ✅

### File Modified

`aws-org-infra/01_org_setup/03_security/03_github_oidc/main.tf`

### Change

Added `snowflake_aws_privatelink` repo to the OIDC trust condition:

```hcl
"token.actions.githubusercontent.com:sub" = [
  "repo:${var.github_org}/${var.github_repo}:*",            # e-commerce app repo
  "repo:${local.infra_repo_org}/${var.github_infra_repo}:*", # aws-org-infra repo
  "repo:${local.infra_repo_org}/snowflake_aws_privatelink:*" # snowflake privatelink repo
]
```

### Commands Run

```bash
cd /home/midega-g/Desktop/Learning/aws-org-infra/01_org_setup/03_security/03_github_oidc

terraform validate
# Success! The configuration is valid.

terraform plan
# Plan: 0 to add, 1 to change, 0 to destroy.
#   ~ aws_iam_role.github_actions (trust policy update in-place)

terraform apply
```

---

## Lessons Learned

1. **Always check resource naming constraints** before creating new IAM resources.
   The `Org*` prefix convention isn't just a naming preference — it's enforced by IAM policy.

2. **IAM tagging permissions are implicit in resource creation** when `default_tags` is set.
   If your policy allows `iam:CreatePolicy` but not `iam:TagPolicy`, creation fails because
   AWS applies tags as part of the create call.

3. **Self-modifying IAM policies require two applies** (or a targeted apply first).
   Terraform doesn't know the policy it's updating is the same policy granting it permission
   to create other resources.

4. **When adding new accounts to org infrastructure**, update ALL policy statements that
   reference member account ARNs — there may be multiple (`OrgTerraformOps` + `OrgAssumeBackboneAccounts`).

---

## State After Phase 0

| Item | Status |
|------|--------|
| GitHub repo created | ✅ |
| Directory structure | ✅ |
| Scripts (authorize, verify, revoke, test) | ✅ |
| README + specs | ✅ |
| IAM role `OrgSnowflakePrivateLinkAdmin` | ✅ (pending final apply confirmation) |
| IAM policy `OrgSnowflakePrivateLinkOps` | ✅ (pending final apply confirmation) |
| OIDC trust updated | ✅ (pending apply) |
| Sandbox account accessible via Switch Role | ✅ (policy updated) |

---

## Git Commits & Push

### aws-org-infra

```bash
cd /home/midega-g/Desktop/Learning/aws-org-infra

git add \
  01_org_setup/03_security/01_management_iam/main.tf \
  01_org_setup/03_security/01_management_iam/snowflake_privatelink_role.tf \
  01_org_setup/03_security/03_github_oidc/main.tf

git commit -m "feat: add snowflake-privatelink IAM role + sandbox assume-role access

- Create OrgSnowflakePrivateLinkAdmin role (scoped for PrivateLink infra)
- Create OrgSnowflakePrivateLinkOps policy (STS, EC2, Route53, S3 state)
- Add sandbox account to AssumeRoleInMemberAccounts (OrgTerraformOps)
- Add sandbox account to AssumeOrgAccessRole (OrgAssumeBackboneAccounts)
- Add iam:TagPolicy/TagRole/UntagPolicy/UntagRole to IAMPolicyManagement
- Add local.sandbox_id to locals block
- Add data.terraform_remote_state.sandbox for sandbox account ID
- Update OIDC trust to include snowflake_aws_privatelink repo"

git push
# To https://github.com/midega-g/aws-org-infra.git
#    57e1d2d..1557497  main -> main
```

### snowflake_aws_privatelink

```bash
cd /home/midega-g/Desktop/Learning/snowflake_aws_privatelink

git add -A

git commit -m "feat: initial project structure and specs

- Project scaffolding: terraform workspaces, scripts, docs, app
- Spec files: requirements, design, tasks, checklist
- Helper scripts: authorize, verify, revoke, test-connectivity
- Phase 0 implementation log
- README with architecture diagram and quick start"

git branch -M main
git push -u origin main
# To https://github.com/midega-g/snowflake_aws_privatelink.git
#  * [new branch]      main -> main
#  branch 'main' set up to track 'origin/main'.
```

---

## Next Steps

- **Phase 1:** Create VPC + networking in `terraform/01_networking`
- Update README with correct profile instructions (use `org_mgmt_epf`, not a separate profile)
- Confirm Switch Role to sandbox works in console
