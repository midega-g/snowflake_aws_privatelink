# ============================================================
# 01_networking/provider.tf
#
# Authenticates as the management account user (org_mgmt_epf),
# then assumes OrganizationAccountAccessRole in the sandbox
# account to create resources in us-west-2.
#
# STS WORKAROUND: The management account credentials originate
# from af-south-1 (opt-in region). AWS provider v6 defaults to
# the regional STS endpoint, which rejects cross-region
# AssumeRole from opt-in regions. Forcing the global STS
# endpoint (sts.amazonaws.com) with sts_region = us-east-1
# resolves this.
# ============================================================

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.sandbox.outputs.sandbox_account_id}:role/OrganizationAccountAccessRole"
  }

  # STS workaround: af-south-1 is opt-in and its regional STS endpoint
  # rejects cross-region AssumeRole. Route through the global endpoint
  # (us-east-1) instead.
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
