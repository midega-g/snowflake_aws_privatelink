# ============================================================
# 04_network_policy/main.tf
#
# Snowflake network policy to restrict account access:
#   - VPC CIDR (10.0.0.0/16) — PrivateLink traffic
#   - Operator IP — debug/admin access from laptop
#   - All other access is blocked
#
# Uses allowed_ip_list directly on the policy (simpler than
# network rules which require a dedicated database/schema).
#
# IMPORTANT: Only apply AFTER PrivateLink is validated.
# Applying prematurely will lock you out of Snowflake.
#
# ROLLBACK: If locked out, connect from EC2 inside VPC and run:
#   ALTER ACCOUNT UNSET NETWORK_POLICY;
# Or: terraform destroy in this workspace.
# ============================================================

# ---- Network Policy ----

resource "snowflake_network_policy" "privatelink_only" {
  name    = "PRIVATELINK_ACCESS_POLICY"
  comment = "Restrict access to VPC PrivateLink (${var.vpc_cidr}) + operator IPs only. All other public access blocked."

  allowed_ip_list = concat([var.vpc_cidr], var.operator_ip)
}

# ---- Activate policy at account level ----

resource "snowflake_account_parameter" "network_policy" {
  key   = "NETWORK_POLICY"
  value = snowflake_network_policy.privatelink_only.name
}
