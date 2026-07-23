# ============================================================
# 02_privatelink/provider.tf
#
# AWS provider: assumes OrganizationAccountAccessRole in sandbox.
# Snowflake provider: connects to the Business Critical account
# for PrivateLink config data source.
# ============================================================

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.sandbox.outputs.sandbox_account_id}:role/OrganizationAccountAccessRole"
  }

  # STS workaround: af-south-1 is an opt-in region whose regional STS
  # endpoint rejects cross-region AssumeRole. Routing through the global
  # endpoint (sts.amazonaws.com) resolves this. The global endpoint
  # requires sts_region = "us-east-1" for request signing.
  sts_region = "us-east-1"

  endpoints {
    sts = "https://sts.amazonaws.com"
  }

  default_tags {
    tags = {
      "project:name"        = var.project_name
      "project:environment" = "sandbox"
      "project:owner"       = "cloudops-team"
      "project:managed-by"  = "terraform"
      "project:repo"        = "snowflake_aws_privatelink"
      "project:cost-center" = "data-platform"
    }
  }
}

provider "snowflake" {
  profile                  = "snowflake-privatelink-profile"
  role                     = "ACCOUNTADMIN"
  preview_features_enabled = ["snowflake_system_get_privatelink_config_datasource"]
}
