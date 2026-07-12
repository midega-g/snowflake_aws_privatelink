#!/usr/bin/env bash
# ============================================================
# verify-privatelink.sh
#
# Checks whether PrivateLink is authorized for the current
# AWS account against Snowflake.
#
# Usage:
#   ./scripts/verify-privatelink.sh
# ============================================================

set -euo pipefail

echo "=== Verifying Snowflake PrivateLink Authorization ==="
echo ""

# Generate fresh federation token
echo "Generating federation token..."
TOKEN_JSON=$(aws sts get-federation-token --name snowflake --output json)

AWS_ACCOUNT_ID=$(echo "$TOKEN_JSON" | jq -r '.FederatedUser.FederatedUserId' | cut -d: -f1)

echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""
echo "Run in Snowflake (ACCOUNTADMIN):"
echo ""
echo "SELECT SYSTEM\$GET_PRIVATELINK("
echo "  '${AWS_ACCOUNT_ID}',"
echo "  '${TOKEN_JSON}'"
echo ");"
echo ""
echo "Expected: 'Account is authorized for PrivateLink.'"
