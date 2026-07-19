output "network_policy_name" {
  description = "Name of the Snowflake network policy."
  value       = snowflake_network_policy.privatelink_only.name
}

output "allowed_sources" {
  description = "Summary of allowed access sources."
  value = {
    vpc_cidr    = var.vpc_cidr
    operator_ips = var.operator_ip
  }
}
