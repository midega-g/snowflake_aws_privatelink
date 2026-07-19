# ============================================================
# 03_ec2_test/data.tf
#
# Remote state lookups and AMI data source.
# ============================================================

# ---- Sandbox account ID ----

data "terraform_remote_state" "sandbox" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "sandbox/terraform.tfstate"
    region = var.state_region
  }
}

# ---- Networking outputs ----

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "projects/snowflake-privatelink/networking/terraform.tfstate"
    region = var.state_region
  }
}

# ---- PrivateLink outputs ----

data "terraform_remote_state" "privatelink" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "projects/snowflake-privatelink/privatelink/terraform.tfstate"
    region = var.state_region
  }
}

# ---- Latest Amazon Linux 2023 AMI ----

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
