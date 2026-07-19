# ============================================================
# 02_privatelink/dns.tf
#
# Route53 private hosted zone and CNAME records for Snowflake
# PrivateLink DNS resolution.
#
# Records:
#   - Account URL (regional)
#   - OCSP URL
#   - Snowsight regionless URL (browser access)
#   - Snowsight regional URL (browser access)
#   - Regionless account URL
#   - Regionless OCSP URL
# ============================================================

locals {
  pl_config = data.snowflake_system_get_privatelink_config.this
  vpce_dns  = aws_vpc_endpoint.snowflake.dns_entry[0].dns_name
}

resource "aws_route53_zone" "snowflake_privatelink" {
  name    = "privatelink.snowflakecomputing.com"
  comment = "Private hosted zone for Snowflake PrivateLink DNS resolution"

  vpc {
    vpc_id = local.vpc_id
  }

  tags = {
    Name = "${var.project_name}-dns"
  }
}

# ---- CNAME: account URL → VPCE regional DNS ----

resource "aws_route53_record" "snowflake_account" {
  zone_id = aws_route53_zone.snowflake_privatelink.zone_id
  name    = local.pl_config.account_url
  type    = "CNAME"
  ttl     = 300
  records = [local.vpce_dns]
}

# ---- CNAME: OCSP URL → VPCE regional DNS ----

resource "aws_route53_record" "snowflake_ocsp" {
  zone_id = aws_route53_zone.snowflake_privatelink.zone_id
  name    = local.pl_config.ocsp_url
  type    = "CNAME"
  ttl     = 300
  records = [local.vpce_dns]
}

# ---- CNAME: Snowsight regionless URL → VPCE regional DNS ----

resource "aws_route53_record" "snowsight_regionless" {
  zone_id = aws_route53_zone.snowflake_privatelink.zone_id
  name    = local.pl_config.regionless_snowsight_url
  type    = "CNAME"
  ttl     = 300
  records = [local.vpce_dns]
}

# ---- CNAME: Snowsight regional URL → VPCE regional DNS ----

resource "aws_route53_record" "snowsight_regional" {
  zone_id = aws_route53_zone.snowflake_privatelink.zone_id
  name    = local.pl_config.snowsight_url
  type    = "CNAME"
  ttl     = 300
  records = [local.vpce_dns]
}

# ---- CNAME: Regionless account URL → VPCE regional DNS ----

resource "aws_route53_record" "regionless_account" {
  zone_id = aws_route53_zone.snowflake_privatelink.zone_id
  name    = local.pl_config.regionless_account_url
  type    = "CNAME"
  ttl     = 300
  records = [local.vpce_dns]
}

# ---- CNAME: Regionless OCSP URL → VPCE regional DNS ----

resource "aws_route53_record" "regionless_ocsp" {
  zone_id = aws_route53_zone.snowflake_privatelink.zone_id
  name    = local.pl_config.regionless_privatelink_ocsp_url
  type    = "CNAME"
  ttl     = 300
  records = [local.vpce_dns]
}
