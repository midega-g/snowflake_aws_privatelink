# 03 EC2 Test

Ephemeral EC2 instance for validating PrivateLink connectivity. Stop after testing; destroy when PrivateLink is confirmed stable.

## Resources Created

- EC2 instance (t3.micro, Amazon Linux 2023) in a public subnet
- Key pair for SSH access
- Security group: SSH (port 22) from operator IP only
- User data: installs telnet and bind-utils (nslookup)

## Prerequisites

- `01_networking` applied
- Operator IP known (passed as variable)

## Usage

```bash
terraform init
terraform apply -var="operator_ip=$(curl -s ifconfig.me)/32"

# SSH in and test
ssh -i <key.pem> ec2-user@<public_ip>
nslookup <account>.us-west-2.privatelink.snowflakecomputing.com
telnet <endpoint_ip> 443
```

## Cleanup

```bash
# Stop (keep for re-testing):
aws ec2 stop-instances --instance-ids <id>

# Destroy (when done):
terraform destroy
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
