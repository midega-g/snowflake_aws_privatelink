# ============================================================
# 02_privatelink/auth.tf
#
# Ephemeral IAM user in the sandbox account for generating the
# federation token required by Snowflake's
# SYSTEM$AUTHORIZE_PRIVATELINK / SYSTEM$GET_PRIVATELINK /
# SYSTEM$REVOKE_PRIVATELINK functions.
#
# WHY: GetFederationToken cannot be called from an assumed-role
# session (AWS hard limitation). The federation token must come
# from IAM user credentials in the account being authorized.
#
# This user has ONLY sts:GetFederationToken — no other access.
# The helper scripts (scripts/authorize-privatelink.sh, etc.)
# read the access key from `terraform output` at runtime.
# ============================================================

resource "aws_iam_user" "privatelink_auth" {
  name = "${var.project_name}-auth"
  path = "/ephemeral/"

  tags = {
    Name            = "${var.project_name}-auth"
    "iam:purpose"   = "privatelink-authorization"
    "iam:ephemeral" = "false"
  }
}

resource "aws_iam_user_policy" "federation_token_only" {
  name = "GetFederationTokenOnly"
  user = aws_iam_user.privatelink_auth.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowGetFederationToken"
        Effect   = "Allow"
        Action   = "sts:GetFederationToken"
        Resource = "arn:aws:sts::${data.terraform_remote_state.sandbox.outputs.sandbox_account_id}:federated-user/*"
      }
    ]
  })
}

resource "aws_iam_access_key" "privatelink_auth" {
  user = aws_iam_user.privatelink_auth.name
}
