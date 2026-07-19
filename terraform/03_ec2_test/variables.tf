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

variable "operator_ip" {
  description = "Operator's public IP in CIDR notation (e.g., 203.0.113.5/32). Used to restrict SSH access."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "snowflake_user" {
  description = "Snowflake username for SnowSQL config (no password stored — prompts at runtime)."
  type        = string
  default     = "SNOWLEARN"
}
