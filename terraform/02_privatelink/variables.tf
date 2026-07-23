variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project identifier used in resource naming and tags."
  type        = string
  default     = "snowflake-privatelink"
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform remote state."
  type        = string
  default     = "ecommerce-tf-state-mgmt"
}

variable "state_region" {
  description = "AWS region of the Terraform state bucket."
  type        = string
  default     = "af-south-1"
}

variable "snowflake_profile" {
  description = "Snowflake config profile name. Set to null in CI (uses env vars instead)."
  type        = string
  default     = "snowflake-privatelink-profile"
}
