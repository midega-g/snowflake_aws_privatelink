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
without `01_networking` deployed. The CI workflow uses `continue-on-error: true` on
the plan step, so it posts the error as a PR comment rather than silently failing.
When `01_networking` is redeployed, `02_privatelink` will plan successfully.

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

3. **Destroyed state breaks downstream workspaces.** If you destroy `01_networking`,
   any workspace that reads its outputs will fail. This is correct — infrastructure
   has a dependency order in both creation and existence.

4. **SnowSQL user_data worked on recreate.** The user_data fix (installing SnowSQL +
   config on first boot) proved itself — no manual installation needed on the fresh EC2.
   However, the initial SnowSQL bootstrap had a path issue (`~/.snowsql` not found)
   that required a clean reinstall.
