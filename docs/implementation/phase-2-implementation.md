# Implementation Log — Phase 2: PrivateLink

## Date: 2026-07-15

---

## Goal

Create the Snowflake PrivateLink infrastructure in the sandbox account (us-west-2):
authorization mechanism, VPC Interface Endpoint, S3 Gateway Endpoint, security group,
and Route53 private DNS. This enables private connectivity from the VPC to Snowflake
without traversing the public internet.

---

## Task 2.0: Auth User for Federation Token ✅

### Problem

`SYSTEM$AUTHORIZE_PRIVATELINK` requires a federation token from the AWS account being
authorized. `sts:GetFederationToken` **cannot** be called from an assumed-role session
(AWS hard limitation). Our workflow assumes into the sandbox via
`OrganizationAccountAccessRole`, so we cannot generate the token directly.

### Solution

Create a minimal IAM user in the sandbox account with only `sts:GetFederationToken`.
The helper scripts (`authorize-privatelink.sh`, `verify-privatelink.sh`,
`revoke-privatelink.sh`) read the access key from `terraform output` at runtime.

### Initial Attempt: Separate Workspace (`01a_privatelink_auth`)

Initially created as a standalone workspace with its own state file
(`projects/snowflake-privatelink/privatelink-auth/terraform.tfstate`).

**Why it was merged into `02_privatelink`:**
- The auth user is not truly ephemeral — it's needed for ongoing verify/revoke operations
- A separate workspace for 3 IAM resources adds unnecessary operational overhead
- The auth user is a prerequisite *for* PrivateLink — it belongs in the same workspace

The `01a` state file remains in S3 (empty, harmless). Resources were destroyed before
merging into `02_privatelink`.

### Files

- `terraform/02_privatelink/auth.tf` — IAM user, inline policy, access key

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| User path `/ephemeral/` | Easy to identify/audit in IAM console |
| Inline policy (not managed) | Single-purpose user; no reuse needed |
| Access key in Terraform output | Scripts read dynamically; no hardcoded creds |
| Kept permanently (not destroyed) | Needed for verify/revoke operations over project lifetime |

---

## Task 2.1: Snowflake Provider Configuration ✅

### Snowflake Config File

```bash
# ~/.snowflake/config (chmod 600)
[default]
organization_name = "<org>"
account_name = "<account>"
user = "<username>"
authenticator = "snowflake"
password = "<password>"
role = "ACCOUNTADMIN"
```

### Provider Block

```hcl
provider "snowflake" {
  profile                  = "default"
  role                     = "ACCOUNTADMIN"
  preview_features_enabled = ["snowflake_system_get_privatelink_config_datasource"]
}
```

### Issues Encountered

**Issue 1: Provider source moved**

The Snowflake provider migrated from `Snowflake-Labs/snowflake` to `snowflakedb/snowflake`.
Using the old source produces a registry warning. Fixed by updating `versions.tf`:

```hcl
snowflake = {
  source  = "snowflakedb/snowflake"  # was Snowflake-Labs/snowflake
  version = ">= 1.0"
}
```

Required deleting `.terraform.lock.hcl` and re-running `terraform init`.

**Issue 2: Attribute names differ from docs**

The spec referenced `privatelink_account_url` and `privatelink_ocsp_url`, but the
actual data source attributes are:

| Spec (wrong) | Actual (correct) |
|--------------|-----------------|
| `privatelink_account_url` | `account_url` |
| `privatelink_ocsp_url` | `ocsp_url` |
| `aws_vpce_id` | `aws_vpce_id` ✓ |

Discovered via `terraform providers schema`. To inspect a specific data source's
attributes without wading through the full schema:

```bash
# List all data sources for a provider
terraform providers schema -json | jq \
  '.provider_schemas["registry.terraform.io/snowflakedb/snowflake"].data_source_schemas | keys'

# Show attributes for a specific data source
terraform providers schema -json | jq \
  '.provider_schemas["registry.terraform.io/snowflakedb/snowflake"].data_source_schemas["snowflake_system_get_privatelink_config"].block.attributes | to_entries[] | {key: .key, type: .value.type}'
```

Pattern: `.provider_schemas["<registry>/<org>/<provider>"].data_source_schemas["<data_source>"].block.attributes`

**Issue 3: Plan hung with placeholder variables**

Initially used `var.snowflake_organization` and `var.snowflake_account`. Switched to
`profile = "default"` to read from `~/.snowflake/config` — avoids duplication and
works non-interactively.

---

## Task 2.2: Snowflake Authorization ✅

### Commands

```bash
# Apply auth user first (targeted)
export AWS_PROFILE=org_mgmt_epf
cd terraform/02_privatelink
terraform apply -target=aws_iam_user.privatelink_auth \
  -target=aws_iam_user_policy.federation_token_only \
  -target=aws_iam_access_key.privatelink_auth

# Generate federation token and SQL
cd ../..
AWS_PROFILE=org_mgmt_epf ./scripts/authorize-privatelink.sh
```

### Script Debugging

**Issue: Script failed silently without `AWS_PROFILE`**

The scripts call `terraform output` which reads from S3 backend. Without `AWS_PROFILE`
set, it can't authenticate to S3 and returns empty strings. The `-z` check then exits.

**Fix:** Always run scripts with `AWS_PROFILE=org_mgmt_epf` prefix (or export it).

### Snowflake SQL Execution

```sql
USE ROLE ACCOUNTADMIN;

SELECT SYSTEM$AUTHORIZE_PRIVATELINK(
  '610269526926',
  '<federation_token_json>'
);
-- Result: "Private link access authorized."
```

**Note:** The expected result message differs from some documentation:
- Actual: `"Private link access authorized."`
- Some docs say: `"Account is authorized for PrivateLink."`

Both indicate success.

### Verifying Authorized Endpoints (Snowflake)

After authorization, query the authorized endpoints directly in Snowflake:

```sql
SELECT
    REPLACE(value:endpointId, '"') AS endpoint_id,
    REPLACE(value:endpointIdType, '"') AS endpoint_type
FROM TABLE(FLATTEN(
    input => PARSE_JSON(SYSTEM$GET_PRIVATELINK_AUTHORIZED_ENDPOINTS())
));
```

This returns the AWS account ID and type (`AWSAccountId`) confirming which accounts
are authorized to connect via PrivateLink.

### How Federation Tokens Work Across Scripts

Each script (`authorize`, `verify`, `revoke`) generates its **own fresh federation token**
on every invocation. This is intentional:

- Federation tokens are temporary session credentials (expire in 12 hours)
- All tokens are derived from the same IAM user access key (`snowflake-privatelink-auth`)
- Snowflake validates "does this token prove ownership of this AWS account?" — not
  "is this the same token used during authorization?"
- Generating fresh tokens per-script means each script works independently at any time,
  without relying on a shared token that may have expired

Analogy: showing your ID at different checkpoints — any valid ID works, it doesn't
have to be the same physical card each time.

---

## Task 2.3: Full Apply ✅

### Commands

```bash
export AWS_PROFILE=org_mgmt_epf
cd terraform/02_privatelink
terraform apply -auto-approve
# Apply complete! Resources: 9 added, 0 changed, 0 destroyed.
```

### Resources Created (12 total: 3 auth + 9 infra)

| Resource | Type |
|----------|------|
| IAM User (`snowflake-privatelink-auth`) | `aws_iam_user` |
| IAM Policy (GetFederationTokenOnly) | `aws_iam_user_policy` |
| IAM Access Key | `aws_iam_access_key` |
| Security Group (endpoint-sg) | `aws_security_group` |
| SG Rule: HTTPS inbound (443) | `aws_security_group_rule` |
| SG Rule: OCSP inbound (80) | `aws_security_group_rule` |
| SG Rule: All outbound | `aws_security_group_rule` |
| VPC Endpoint - Snowflake (Interface) | `aws_vpc_endpoint` |
| VPC Endpoint - S3 (Gateway) | `aws_vpc_endpoint` |
| Route53 Private Hosted Zone | `aws_route53_zone` |
| CNAME - Account URL | `aws_route53_record` |
| CNAME - OCSP URL | `aws_route53_record` |

### Outputs

```
auth_user_access_key_id           = (from terraform output)
auth_user_secret_access_key       = (sensitive)
hosted_zone_id                    = (from terraform output)
s3_endpoint_id                    = (from terraform output)
sandbox_account_id                = "610269526926"
security_group_id                 = (from terraform output)
snowflake_privatelink_account_url = "qbb21532.us-west-2.privatelink.snowflakecomputing.com"
vpce_dns_name                     = (from terraform output)
vpce_id                           = (from terraform output)
```

---

## Cost Estimate — Phase 2

AWS published pricing for us-west-2 (effective 2026-07-01).

### Phase 2 Resources (monthly)

| Resource | Unit Price | Quantity | Monthly Cost |
|----------|-----------|----------|-------------|
| VPC Interface Endpoint (Snowflake) | $0.01/hour/AZ | 3 AZs × 730 hrs | $21.90 |
| VPC Endpoint data processing | $0.01/GB | ~5 GB (light usage) | $0.05 |
| S3 Gateway Endpoint | Free | 1 | $0.00 |
| Route53 Private Hosted Zone | $0.50/month | 1 zone | $0.50 |
| Route53 queries | $0.40/million | ~1,000 queries | $0.00 |
| IAM User + Access Key | Free | 1 | $0.00 |
| Security Group | Free | 1 | $0.00 |
| **Phase 2 Total** | | | **~$22.45/month** |

### Cumulative Cost (All Phases)

| Phase | Monthly Cost | Cumulative |
|-------|-------------|-----------|
| Phase 0 (IAM) | $0.01 | $0.01 |
| Phase 1 (Networking) | $36.55 | $36.56 |
| Phase 2 (PrivateLink) | $22.45 | **$59.01/month** |

### Cost Drivers

- **NAT Gateway** (~$36.50/month) — 62% of total spend. Can be destroyed when not needed.
- **VPC Interface Endpoint** (~$21.90/month) — 37% of total spend. Required for PrivateLink.
- Everything else is free or negligible.

### Cost Optimization Notes

- If the project is idle, destroy NAT Gateway to save ~$36/month:
  ```bash
  cd terraform/01_networking
  terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat
  ```
  PrivateLink and VPC endpoints are unaffected (they don't route through NAT).

- The VPC Interface Endpoint is the irreducible cost of PrivateLink — $21.90/month
  minimum to maintain private connectivity.

---

## Lessons Learned

1. **`sts:GetFederationToken` only works from IAM user credentials.** Assumed-role
   sessions, federated sessions, and root credentials cannot call it. When your
   workflow uses AssumeRole exclusively, you need a dedicated IAM user for this
   one operation.

2. **Snowflake provider attribute names don't match the SQL function output names.**
   `SYSTEM$GET_PRIVATELINK_CONFIG` returns keys like `privatelink-account-url` (with
   hyphens), but the Terraform data source uses `account_url` (underscored, shortened).
   Always verify with `terraform providers schema -json`.

3. **Snowflake provider source has migrated.** `Snowflake-Labs/snowflake` →
   `snowflakedb/snowflake`. Old source still works but produces warnings.
   Delete `.terraform.lock.hcl` when changing provider source.

4. **Use `profile` for Snowflake auth, not variables.** Passing org/account as
   variables duplicates what's already in `~/.snowflake/config` and requires
   `-var` flags on every plan/apply. Profile-based auth is simpler and matches
   the AWS pattern (`AWS_PROFILE`).

5. **Scripts that call `terraform output` need S3 backend access.** The state is
   in S3, so `AWS_PROFILE` must be set even for scripts that don't create AWS
   resources directly.

6. **Targeted apply is fine for bootstrapping circular dependencies.** The auth
   user must exist before authorization, but authorization must happen before
   the VPC endpoint succeeds. Using `-target` for the auth resources first,
   then full apply after authorization, handles this cleanly.

---

## Spec Changes Made

| File | Change |
|------|--------|
| `.kiro/specs/02-design.md` | Updated provider config (profile-based), repo structure (auth.tf, data.tf), security section, attribute name in checklist |
| `.kiro/specs/03-tasks.md` | Fixed attribute names, added Task 2.1a (auth user) |

---

## State After Phase 2

| Item | Status |
|------|--------|
| Auth IAM user in sandbox | ✅ |
| Snowflake PrivateLink authorized | ✅ ("Private link access authorized.") |
| Security Group (443 + 80 from VPC CIDR) | ✅ |
| VPC Interface Endpoint (3 AZs) | ✅ |
| S3 Gateway Endpoint | ✅ |
| Route53 Private Hosted Zone | ✅ |
| CNAME: account URL → VPCE DNS | ✅ |
| CNAME: OCSP URL → VPCE DNS | ✅ |
| Specs updated | ✅ |

---

## Pending

- [ ] Commit and push Phase 2 changes
- [ ] **Phase 3:** EC2 test instance for connectivity validation
- [ ] **Phase 4:** Validate connectivity (nslookup, telnet, SnowSQL)
- [ ] **Phase 5:** Network policy (block public access after validation)
