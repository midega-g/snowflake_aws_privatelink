# ============================================================
# 03_ec2_test/provider.tf
#
# Assumes OrganizationAccountAccessRole in the sandbox account
# to create EC2 test resources in us-west-2.
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
