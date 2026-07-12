#!/usr/bin/env bash
# ============================================================
# test-connectivity.sh
#
# Run this FROM INSIDE the EC2 test instance (via SSH).
# Tests DNS resolution and port connectivity to Snowflake
# via PrivateLink.
#
# Prerequisites (installed via EC2 user_data):
#   - nslookup (bind-utils)
#   - telnet
#
# Usage:
#   ./test-connectivity.sh <snowflake_account> <region>
#
# Example:
#   ./test-connectivity.sh xy12345 us-east-1
# ============================================================

set -euo pipefail

ACCOUNT="${1:-}"
REGION="${2:-us-east-1}"

if [ -z "$ACCOUNT" ]; then
  echo "Usage: $0 <snowflake_account> [region]"
  echo "Example: $0 xy12345 us-east-1"
  exit 1
fi

FQDN="${ACCOUNT}.${REGION}.privatelink.snowflakecomputing.com"
OCSP_FQDN="ocsp.${ACCOUNT}.${REGION}.privatelink.snowflakecomputing.com"

echo "=== Snowflake PrivateLink Connectivity Test ==="
echo ""
echo "Account:  $ACCOUNT"
echo "Region:   $REGION"
echo "FQDN:     $FQDN"
echo "OCSP:     $OCSP_FQDN"
echo ""

# Test 1: DNS Resolution
echo "--- Test 1: DNS Resolution (nslookup) ---"
echo ""
echo "Resolving $FQDN..."
nslookup "$FQDN" || echo "FAILED: DNS resolution failed"
echo ""
echo "Resolving $OCSP_FQDN..."
nslookup "$OCSP_FQDN" || echo "FAILED: OCSP DNS resolution failed"
echo ""

# Test 2: Port 443 (HTTPS)
echo "--- Test 2: Port 443 (HTTPS) ---"
echo ""
# Extract IPs from nslookup
IPS=$(nslookup "$FQDN" 2>/dev/null | grep "Address:" | tail -n +2 | awk '{print $2}')

if [ -z "$IPS" ]; then
  echo "FAILED: No IPs resolved. Cannot test port connectivity."
  exit 1
fi

for IP in $IPS; do
  echo -n "  telnet $IP 443 ... "
  if timeout 5 bash -c "echo > /dev/tcp/$IP/443" 2>/dev/null; then
    echo "CONNECTED ✓"
  else
    echo "FAILED ✗"
  fi
done
echo ""

# Test 3: Port 80 (OCSP)
echo "--- Test 3: Port 80 (OCSP Cache) ---"
echo ""
for IP in $IPS; do
  echo -n "  telnet $IP 80 ... "
  if timeout 5 bash -c "echo > /dev/tcp/$IP/80" 2>/dev/null; then
    echo "CONNECTED ✓"
  else
    echo "FAILED ✗"
  fi
done
echo ""

echo "=== Test Complete ==="
