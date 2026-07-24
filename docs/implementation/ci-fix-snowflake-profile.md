# Implementation Log — CI/CD Fix: Snowflake Profile & Empty State

## Date: 2026-07-23

---

## Context

After destroying all AWS resources and renaming the Snowflake profile from `default`
to `snowflake-privatelink-profile`, the CI/CD pipeline failed on the next push to main.

---

## CI Errors (2 issues)

### Issue 1: Snowflake Config Not Found on Runner

```
Error: could not retrieve "snowflake-privatelink-profile" profile config from file
/home/runner/.snowflake/config: could not load config file: stat /home/runner/.snowflake/config:
no such file or directory
```

**Cause:** The Snowflake provider was hardcoded to use `profile = "snowflake-privatelink-profile"`,
which reads from `~/.snowflake/config`. GitHub Actions runners don't have this file — they
use environment variables from repository secrets.

**Fix:** Make the profile configurable via a variable with a local default:

```hcl
variable "snowflake_profile" {
  description = "Snowflake config profile name. Set to null in CI (uses env vars instead)."
  type        = string
  default     = "snowflake-privatelink-profile"
}

provider "snowflake" {
  profile = var.snowflake_profile
  role    = "ACCOUNTADMIN"
}
```

In CI, pass `-var='snowflake_profile=null'` — when profile is null, the Snowflake
provider falls back to environment variables (`SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`,
`SNOWFLAKE_ACCOUNT_NAME`, `SNOWFLAKE_ORGANIZATION_NAME`) which are set from GitHub secrets.

Locally, the default (`snowflake-privatelink-profile`) reads from `~/.snowflake/config`
as before — no `-var` needed.

### Issue 2: Empty Networking State

```
Error: Unsupported attribute
  on main.tf line 11, in locals:
  11:   vpc_id = data.terraform_remote_state.networking.outputs.vpc_id
    │ data.terraform_remote_state.networking.outputs is object with no attributes
This object does not have an attribute named "vpc_id".
```

**Cause:** All resources were destroyed. The `01_networking` state file exists but
has no outputs (empty state). The `02_privatelink` workspace references those outputs
and fails because they don't exist.

**Resolution:** This is expected behavior — `02_privatelink` cannot plan or apply
without `01_networking` deployed.

### Handling Downstream Plan Failures in CI

When infrastructure is torn down, downstream workspaces (`02_privatelink`) cannot
plan because upstream state is empty. Three approaches were considered:

| Approach | How it works | Tradeoff |
|----------|-------------|----------|
| **Remove downstream from CI** | Only run `01_networking` in CI — it has no dependencies | Clean CI output, but `02_privatelink` code changes aren't validated |
| **Conditional execution** | Check if upstream state is populated before running downstream plan | Complex workflow logic, extra API calls to check state |
| **Accept the failure (chosen)** | `continue-on-error: true` on plan step — CI shows error but doesn't block | Job shows "failed" in GitHub UI but workflow continues; error is informative |

**Why Option 3 (accept the failure) was chosen:**

1. **The error is informative, not harmful.** It tells you "privatelink can't be
   planned without networking deployed" — which is correct and useful.
2. **No code changes needed when infra is redeployed.** Once `01_networking` is
   applied (locally or via CI), `02_privatelink` plan succeeds automatically.
3. **Both workspaces are validated when infra exists.** During active development
   with live infrastructure, both plans pass — you get full coverage.
4. **Minimal workflow complexity.** No conditional logic, no state-checking scripts,
   no maintenance burden.

**When to switch approaches:**
- If the "failed" status on `plan-privatelink` bothers you in GitHub UI → remove it from CI
- If you need both workspaces validated without deploying → not possible (Terraform needs live state)
- If moving to production (infra always up) → re-enable apply jobs, both plans will always pass

---

## Changes Made

### Terraform Files

| File | Change |
|------|--------|
| `terraform/02_privatelink/provider.tf` | `profile` → `var.snowflake_profile` |
| `terraform/02_privatelink/variables.tf` | Added `snowflake_profile` variable (default: `snowflake-privatelink-profile`) |
| `terraform/04_network_policy/provider.tf` | `profile` → `var.snowflake_profile` |
| `terraform/04_network_policy/variables.tf` | Added `snowflake_profile` variable (default: `snowflake-privatelink-profile`) |

### CI Workflow

| Step | Change |
|------|--------|
| `plan-privatelink` | Added `-var='snowflake_profile=null'` to plan command |
| `apply-privatelink` | Added `-var='snowflake_profile=null'` to apply command |

### How It Works

| Environment | Profile value | Auth method |
|-------------|--------------|-------------|
| Local (your machine) | `snowflake-privatelink-profile` (default) | Reads `~/.snowflake/config` |
| CI (GitHub Actions) | `null` (passed via `-var`) | Reads env vars from secrets |

---

## Network Policy Lockout (Again)

During the destroy process, Terraform couldn't connect to Snowflake because our IP
changed to `41.84.154.166` (not in the allowed list). Recovery:

1. Created EC2 inside VPC (`terraform apply` in `03_ec2_test`)
2. SnowSQL was pre-installed via user_data this time ✅
3. Ran `ALTER ACCOUNT UNSET NETWORK_POLICY` from EC2
4. Destroyed all resources in order: 04 → 03 → 02 → 01

**Note:** `app.snowflake.com` was also blocked — the network policy affected all
access paths. EC2 inside VPC remains the only reliable recovery method.

---

## Lesson Learned

1. **CI and local need different auth paths.** Local uses config files, CI uses env
   vars. Make the auth method configurable (variable with default) rather than
   hardcoding either approach.

2. **`profile = null` triggers env var fallback.** When the Snowflake provider's
   profile is null/unset, it reads from `SNOWFLAKE_*` environment variables. This
   is the intended CI pattern.

3. **Passing `-var='snowflake_profile=null'` sends the string "null", not actual null.**
   Terraform CLI cannot pass a true null value. The fix is to pass an empty string
   (`-var='snowflake_profile='`) and use a conditional in the provider:
   ```hcl
   profile = var.snowflake_profile != "" ? var.snowflake_profile : null
   ```

4. **Destroyed state breaks downstream *plan* but not downstream *apply*.**
   If `01_networking` state is empty, `02_privatelink` plan fails because outputs
   don't exist. However, in the CI workflow, the apply job for `02_privatelink`
   depends on `apply-networking` completing first (`needs: [apply-networking]`),
   so by the time privatelink applies, networking state is populated.
   
   The plan-only check (used in PRs) will still fail if upstream state is empty —
   this is expected and informative: "you can't deploy this until networking exists."

5. **SnowSQL user_data worked on recreate.** The user_data fix (installing SnowSQL +
   config on first boot) proved itself — no manual installation needed on the fresh EC2.
   However, the initial SnowSQL bootstrap had a path issue (`~/.snowsql` not found)
   that required a clean reinstall.

6. **CI apply creates real resources.** When the CI workflow includes apply jobs,
   every merge to main that touches `terraform/` files creates AWS resources. For
   test/sandbox projects, switch to **plan-only CI** (validate code correctness
   without deploying) and apply manually when infrastructure is needed. The apply
   jobs are commented out in the workflow for reference — uncomment when moving to
   production where auto-deploy is desired.
