# ============================================================
# 03_ec2_test/main.tf
#
# Ephemeral EC2 instance for validating Snowflake PrivateLink
# connectivity. Placed in a public subnet with SSH access
# restricted to the operator's IP.
#
# LIFECYCLE:
#   1. terraform apply → instance running
#   2. SSH in, run test-connectivity.sh
#   3. Stop instance (or leave running for re-testing)
#   4. terraform destroy when PrivateLink is confirmed stable
# ============================================================

locals {
  vpc_id                    = data.terraform_remote_state.networking.outputs.vpc_id
  public_subnet_ids         = data.terraform_remote_state.networking.outputs.public_subnet_ids
  privatelink_url           = data.terraform_remote_state.privatelink.outputs.snowflake_privatelink_account_url
  privatelink_account_locator = split(".", local.privatelink_url)[0]
}

# ---- Key Pair ----

resource "tls_private_key" "test" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "test" {
  key_name   = "${var.project_name}-test-key"
  public_key = tls_private_key.test.public_key_openssh

  tags = {
    Name = "${var.project_name}-test-key"
  }
}

resource "local_file" "private_key" {
  content         = tls_private_key.test.private_key_pem
  filename        = "${path.module}/${var.project_name}-test-key.pem"
  file_permission = "0400"
}

# ---- Security Group ----

resource "aws_security_group" "ec2_test" {
  name        = "${var.project_name}-ec2-test-sg"
  description = "SSH from operator IP only"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project_name}-ec2-test-sg"
  }
}

resource "aws_security_group_rule" "ssh_inbound" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.operator_ip]
  description       = "SSH from operator IP"
  security_group_id = aws_security_group.ec2_test.id
}

resource "aws_security_group_rule" "all_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound"
  security_group_id = aws_security_group.ec2_test.id
}

# ---- EC2 Instance ----

resource "aws_instance" "test" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = local.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2_test.id]
  key_name                    = aws_key_pair.test.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y bind-utils telnet nc unzip

    # Install SnowSQL 1.5.0
    cd /tmp
    curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.5/linux_x86_64/snowsql-1.5.0-linux_x86_64.bash
    SNOWSQL_DEST=/home/ec2-user/bin SNOWSQL_LOGIN_SHELL=/home/ec2-user/.bashrc bash snowsql-1.5.0-linux_x86_64.bash

    # SnowSQL config for PrivateLink (no password stored)
    mkdir -p /home/ec2-user/.snowflake
    cat > /home/ec2-user/.snowflake/connections.toml << 'TOML'
    [default]
    account = "${local.privatelink_account_locator}.${var.aws_region}.privatelink"
    user = "${var.snowflake_user}"
    TOML
    chown -R ec2-user:ec2-user /home/ec2-user/.snowflake /home/ec2-user/bin
  EOF

  tags = {
    Name = "${var.project_name}-test"
  }
}
