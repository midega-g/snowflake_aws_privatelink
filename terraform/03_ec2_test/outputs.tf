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
