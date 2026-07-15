# ============================================================
# 02_privatelink/main.tf
#
# Creates the Snowflake PrivateLink infrastructure:
#   - Security group for VPC endpoint
#   - VPC Interface Endpoint (Snowflake PrivateLink)
#   - VPC Gateway Endpoint (S3 internal stage traffic)
# ============================================================

locals {
  vpc_id             = data.terraform_remote_state.networking.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.networking.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids
  private_rt_id      = data.terraform_remote_state.networking.outputs.private_route_table_id
}

# ---- Snowflake PrivateLink Config ----

data "snowflake_system_get_privatelink_config" "this" {}

# ---- Security Group ----

resource "aws_security_group" "snowflake_privatelink" {
  name        = "${var.project_name}-endpoint-sg"
  description = "Allow HTTPS and OCSP from VPC CIDR to Snowflake PrivateLink endpoint"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project_name}-endpoint-sg"
  }
}

resource "aws_security_group_rule" "https_inbound" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [local.vpc_cidr]
  description       = "HTTPS from VPC CIDR"
  security_group_id = aws_security_group.snowflake_privatelink.id
}

resource "aws_security_group_rule" "ocsp_inbound" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [local.vpc_cidr]
  description       = "OCSP from VPC CIDR"
  security_group_id = aws_security_group.snowflake_privatelink.id
}

resource "aws_security_group_rule" "all_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound"
  security_group_id = aws_security_group.snowflake_privatelink.id
}

# ---- VPC Interface Endpoint (Snowflake) ----

resource "aws_vpc_endpoint" "snowflake" {
  vpc_id              = local.vpc_id
  service_name        = data.snowflake_system_get_privatelink_config.this.aws_vpce_id
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.snowflake_privatelink.id]
  private_dns_enabled = false

  tags = {
    Name = "${var.project_name}-endpoint"
  }
}

# ---- VPC Gateway Endpoint (S3) ----

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [local.private_rt_id]

  tags = {
    Name = "${var.project_name}-s3-gateway"
  }
}
