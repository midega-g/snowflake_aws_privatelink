variable "project_name" {
  description = "Project identifier used in resource naming."
  type        = string
  default     = "snowflake-privatelink"
}

variable "vpc_cidr" {
  description = "VPC CIDR block (traffic from PrivateLink endpoints)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "operator_ip" {
  description = "Operator's public IP(s) in CIDR notation for debug/admin access. Can be a single IP or list."
  type        = list(string)
}
