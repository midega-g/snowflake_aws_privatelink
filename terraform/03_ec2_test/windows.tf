# ============================================================
# 03_ec2_test/windows.tf
#
# Windows EC2 instance for browser-based Snowsight validation
# via RDP. Proves PrivateLink works for web UI access from
# inside the VPC.
#
# USAGE:
#   1. terraform apply → instance running
#   2. Retrieve admin password: terraform output windows_password_command
#   3. RDP to public IP on port 3389
#   4. Open browser → navigate to Snowsight PrivateLink URL
# ============================================================

# ---- Latest Windows Server 2022 AMI ----

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
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

# ---- Security Group (RDP) ----

resource "aws_security_group" "windows_test" {
  name        = "${var.project_name}-windows-test-sg"
  description = "RDP from operator IP only"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project_name}-windows-test-sg"
  }
}

resource "aws_security_group_rule" "rdp_inbound" {
  type              = "ingress"
  from_port         = 3389
  to_port           = 3389
  protocol          = "tcp"
  cidr_blocks       = [var.operator_ip]
  description       = "RDP from operator IP"
  security_group_id = aws_security_group.windows_test.id
}

resource "aws_security_group_rule" "windows_https_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound"
  security_group_id = aws_security_group.windows_test.id
}

# ---- Windows EC2 Instance ----

resource "aws_instance" "windows_test" {
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = "t3.small"
  subnet_id                   = local.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.windows_test.id]
  key_name                    = aws_key_pair.test.key_name
  associate_public_ip_address = true
  get_password_data           = true

  user_data = <<-EOF
    <powershell>
    # Enable Remote Desktop
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0

    # Enable Windows Firewall rule for RDP
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

    # Ensure RDP service is running
    Set-Service -Name "TermService" -StartupType Automatic
    Start-Service -Name "TermService"
    </powershell>
  EOF

  tags = {
    Name = "${var.project_name}-windows-test"
  }
}
