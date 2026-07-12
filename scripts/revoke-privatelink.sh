#!/usr/bin/env bash
# ============================================================
# revoke-privatelink.sh
#
# Revokes PrivateLink authorization for the current AWS account.
# Use this for cleanup or if you need to re-authorize.
#
# Usage:
#   ./scripts/revoke-privatelink.sh
# ============================================================

set -euo pipefail

echo "=== Revoking Snowflake PrivateLink Authorization ==="
echo ""
echo "WARNING: This will disable PrivateLink connectivity."
echo "         Any services relying on PrivateLink will lose access."
echo ""
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# Generate fresh federation token
echo "Generating federation token..."
TOKEN_JSON=$(aws sts get-federation-token --name snowflake --output json)

AWS_ACCOUNT_ID=$(echo "$TOKEN_JSON" | jq -r '.FederatedUser.FederatedUserId' | cut -d: -f1)

echo ""
echo "Run in Snowflake (ACCOUNTADMIN):"
echo ""
echo "SELECT SYSTEM\$REVOKE_PRIVATELINK("
echo "  '${AWS_ACCOUNT_ID}',"
echo "  '${TOKEN_JSON}'"
echo ");"
echo ""
echo "Expected: 'Private link access revoked.'"
