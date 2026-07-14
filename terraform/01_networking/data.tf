# ============================================================
# 01_networking/data.tf
#
# Data sources and remote state lookups.
# ============================================================

# ---- Sandbox account ID from aws-org-infra state ----

data "terraform_remote_state" "sandbox" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "sandbox/terraform.tfstate"
    region = var.state_region
  }
}
