# ============================================================
# 02_privatelink/data.tf
#
# Remote state lookups for upstream dependencies.
# ============================================================

# ---- Sandbox account ID (from aws-org-infra) ----

data "terraform_remote_state" "sandbox" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "sandbox/terraform.tfstate"
    region = var.state_region
  }
}

# ---- Networking outputs (from 01_networking) ----

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "projects/snowflake-privatelink/networking/terraform.tfstate"
    region = var.state_region
  }
}
