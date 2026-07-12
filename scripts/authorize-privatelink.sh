#!/usr/bin/env bash
# ============================================================
# authorize-privatelink.sh
#
# One-time script to authorize AWS PrivateLink for Snowflake.
# Generates a federation token and outputs the SQL to run in
# Snowflake with ACCOUNTADMIN role.
#
# Prerequisites:
#   - AWS CLI configured (profile with sts:GetFederationToken)
#   - jq installed
#   - Snowflake account with ACCOUNTADMIN access
#
# Usage:
#   ./scripts/authorize-privatelink.sh
# ============================================================

set -euo pipefail

echo "=== Snowflake PrivateLink Authorization ==="
echo ""

# Generate federation token
echo "Generating federation token..."
TOKEN_JSON=$(aws sts get-federation-token --name snowflake --output json)

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to generate federation token."
  echo "Ensure your AWS profile has sts:GetFederationToken permission."
  exit 1
fi

# Extract AWS Account ID from FederatedUserId
AWS_ACCOUNT_ID=$(echo "$TOKEN_JSON" | jq -r '.FederatedUser.FederatedUserId' | cut -d: -f1)

echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "Token expires:  $(echo "$TOKEN_JSON" | jq -r '.Credentials.Expiration')"
echo ""
echo "============================================"
echo "Run the following SQL in Snowflake (ACCOUNTADMIN role):"
echo "============================================"
echo ""
echo "USE ROLE ACCOUNTADMIN;"
echo ""
echo "SELECT SYSTEM\$AUTHORIZE_PRIVATELINK("
echo "  '${AWS_ACCOUNT_ID}',"
echo "  '${TOKEN_JSON}'"
echo ");"
echo ""
echo "============================================"
echo "To VERIFY authorization afterwards, run:"
echo "============================================"
echo ""
echo "SELECT SYSTEM\$GET_PRIVATELINK("
echo "  '${AWS_ACCOUNT_ID}',"
echo "  '$(aws sts get-federation-token --name snowflake --output json)'"
echo ");"
echo ""
echo "Expected: 'Account is authorized for PrivateLink.'"
