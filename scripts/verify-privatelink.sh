#!/usr/bin/env bash
# ============================================================
# verify-privatelink.sh
#
# Checks whether PrivateLink is authorized for the sandbox
# AWS account against Snowflake. Reads credentials from the
# 02_privatelink Terraform workspace.
#
# Usage:
#   ./scripts/verify-privatelink.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_DIR="${SCRIPT_DIR}/../terraform/02_privatelink"

echo "=== Verifying Snowflake PrivateLink Authorization ==="
echo ""

# Read credentials from Terraform output
echo "Reading credentials from terraform/02_privatelink..."

if [ ! -d "$AUTH_DIR/.terraform" ]; then
  echo "ERROR: 02_privatelink not initialized."
  echo "Run: cd terraform/02_privatelink && terraform init && terraform apply"
  exit 1
fi

ACCESS_KEY_ID=$(cd "$AUTH_DIR" && terraform output -raw auth_user_access_key_id 2>/dev/null)
SECRET_ACCESS_KEY=$(cd "$AUTH_DIR" && terraform output -raw auth_user_secret_access_key 2>/dev/null)
AWS_ACCOUNT_ID=$(cd "$AUTH_DIR" && terraform output -raw sandbox_account_id 2>/dev/null)

if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "ERROR: Could not read outputs from 02_privatelink."
  echo "Ensure the workspace is applied: cd terraform/02_privatelink && terraform apply"
  exit 1
fi

echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

# Generate fresh federation token
echo "Generating federation token..."
TOKEN_JSON=$(AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
  AWS_DEFAULT_REGION="us-west-2" \
  aws sts get-federation-token --name snowflake-privatelink --output json 2>&1)

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to generate federation token."
  echo "$TOKEN_JSON"
  exit 1
fi

echo ""
echo "Run in Snowflake (ACCOUNTADMIN):"
echo ""
echo "SELECT SYSTEM\$GET_PRIVATELINK("
echo "  '${AWS_ACCOUNT_ID}',"
echo "  '${TOKEN_JSON}'"
echo ");"
echo ""
echo "Expected: 'Account is authorized for PrivateLink.'"
