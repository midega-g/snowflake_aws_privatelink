output "instance_id" {
  description = "ID of the EC2 test instance."
  value       = aws_instance.test.id
}

output "public_ip" {
  description = "Public IP address of the EC2 test instance."
  value       = aws_instance.test.public_ip
}

output "private_key_path" {
  description = "Path to the SSH private key file."
  value       = local_file.private_key.filename
}

output "ssh_command" {
  description = "SSH command to connect to the test instance."
  value       = "ssh -i ${local_file.private_key.filename} ec2-user@${aws_instance.test.public_ip}"
}

output "test_command" {
  description = "Command to run the connectivity test from inside the instance."
  value       = "nslookup ${local.privatelink_url}"
}

# ---- Windows outputs ----

output "windows_instance_id" {
  description = "ID of the Windows EC2 test instance."
  value       = aws_instance.windows_test.id
}

output "windows_public_ip" {
  description = "Public IP of the Windows EC2 test instance."
  value       = aws_instance.windows_test.public_ip
}

output "windows_admin_password" {
  description = "Encrypted admin password (decrypt with private key)."
  value       = aws_instance.windows_test.password_data
  sensitive   = true
}

output "windows_password_command" {
  description = "Command to decrypt the Windows admin password (requires AWS_PROFILE already set)."
  value       = "terraform output -raw windows_admin_password | base64 -d | openssl pkeyutl -decrypt -inkey ${local_file.private_key.filename}"
}

output "snowsight_privatelink_url" {
  description = "Snowsight URL to open in the Windows browser."
  value       = "https://${local.privatelink_url}"
}
