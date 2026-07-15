# ---- Auth user outputs (used by scripts/) ----

output "auth_user_access_key_id" {
  description = "Access key ID for the auth user. Used by authorize/verify/revoke scripts."
  value       = aws_iam_access_key.privatelink_auth.id
}

output "auth_user_secret_access_key" {
  description = "Secret access key for the auth user. Used by authorize/verify/revoke scripts."
  value       = aws_iam_access_key.privatelink_auth.secret
  sensitive   = true
}

output "sandbox_account_id" {
  description = "AWS account ID of the sandbox (passed to SYSTEM$AUTHORIZE_PRIVATELINK)."
  value       = data.terraform_remote_state.sandbox.outputs.sandbox_account_id
}

# ---- PrivateLink outputs ----

output "vpce_id" {
  description = "ID of the Snowflake VPC Interface Endpoint."
  value       = aws_vpc_endpoint.snowflake.id
}

output "vpce_dns_name" {
  description = "Regional DNS name of the Snowflake VPC Endpoint."
  value       = aws_vpc_endpoint.snowflake.dns_entry[0].dns_name
}

output "security_group_id" {
  description = "ID of the PrivateLink endpoint security group."
  value       = aws_security_group.snowflake_privatelink.id
}

output "s3_endpoint_id" {
  description = "ID of the S3 Gateway Endpoint."
  value       = aws_vpc_endpoint.s3.id
}

output "hosted_zone_id" {
  description = "ID of the Route53 private hosted zone."
  value       = aws_route53_zone.snowflake_privatelink.zone_id
}

output "snowflake_privatelink_account_url" {
  description = "Snowflake account URL for PrivateLink connections."
  value       = data.snowflake_system_get_privatelink_config.this.account_url
}
