# ============================================================
# 04_network_policy/provider.tf
#
# Snowflake provider only — no AWS resources in this workspace.
# Reads credentials from ~/.snowflake/config (profile: default).
#
# NOTE: The S3 backend still requires AWS credentials to
# read/write state. Ensure AWS_PROFILE is exported.
# ============================================================

provider "snowflake" {
  profile = var.snowflake_profile != "" ? var.snowflake_profile : null
  role    = "ACCOUNTADMIN"
}
