# Implementation Log — Phase 5: Network Policy

## Date: 2026-07-19

---

## Goal

Block all public access to the Snowflake account except from the VPC (PrivateLink)
and the operator's IPs (debug/admin). Demonstrate enforcement by temporarily removing
allowed IPs and confirming access is blocked.

---

## Task 5.1: Create Network Policy ✅

### Initial Approach: Network Rules (Failed)

First attempted using `snowflake_network_rule` resources with `database = "SNOWFLAKE"`
and `schema = "NETWORK"`:

```
Error: [errors.go:23] object does not exist or not authorized
```

**Root cause:** Network rules require an existing user-created database and schema.
The `SNOWFLAKE` system database doesn't have a `NETWORK` schema, and you can't create
schemas in system databases.

**Resolution:** Switched to `allowed_ip_list` directly on the `snowflake_network_policy`
resource. This is simpler and doesn't require a dedicated database/schema for network
objects.

### Final Implementation

```hcl
resource "snowflake_network_policy" "privatelink_only" {
  name    = "PRIVATELINK_ACCESS_POLICY"
  comment = "Restrict access to VPC PrivateLink + operator IPs only."

  allowed_ip_list = concat([var.vpc_cidr], var.operator_ip)
}

resource "snowflake_account_parameter" "network_policy" {
  key   = "NETWORK_POLICY"
  value = snowflake_network_policy.privatelink_only.name
}
```

### Variables

- `vpc_cidr` — `10.0.0.0/16` (default, covers all PrivateLink VPCE ENI IPs)
- `operator_ip` — `list(string)` (multiple IPs supported, no default — must be provided)

### Apply

```bash
export AWS_PROFILE=org_mgmt_epf
cd terraform/04_network_policy
terraform init
terraform apply -var='operator_ip=["102.208.164.205/32","102.203.137.234/32"]'
# Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

---

## Task 5.2: Lockout Incident and Recovery ✅

### What Happened

After applying the policy with only `102.208.164.205/32` as the operator IP, the
Terraform Snowflake provider was blocked on subsequent operations:

```
Error: open snowflake connection: 390422 (08004): Incoming request with IP/Token
102.203.137.234 is not allowed to access Snowflake.
```

**Root cause:** The CLI/Terraform exits through a different IP (`102.203.137.234`)
than what `curl ifconfig.me` reports (`102.208.164.205`). In this case, the browser
extension uBlock Origin Lite (powered by Windscribe) routes browser traffic through
Los Angeles, resulting in a different exit IP than direct CLI traffic. This is why
two IPs are needed in the allowed list — without the extension, a single IP would
suffice.

Other scenarios where multiple exit IPs occur:
- ISPs using carrier-grade NAT (CGNAT) with multiple exit IPs
- Split DNS or proxy configurations
- VPN split tunneling (some traffic goes through VPN, some direct)

### Recovery Steps

1. SSH into the Linux EC2 inside the VPC (VPC CIDR `10.0.0.0/16` is always allowed):

```bash
ssh -i ./snowflake-privatelink-test-key.pem ec2-user@<linux_ec2_ip>
```

2. Unset the network policy from inside the VPC:

```bash
SNOWSQL_PWD='<password>' ~/bin/snowsql \
  -a qbb21532.us-west-2.privatelink -u SNOWLEARN \
  -o friendly=false \
  -q "USE ROLE ACCOUNTADMIN; ALTER ACCOUNT UNSET NETWORK_POLICY;"
```

3. Re-apply Terraform with both IPs:

```bash
terraform apply -var='operator_ip=["102.208.164.205/32","102.203.137.234/32"]'
```

### Key Takeaway

Always include **all** IPs your connections might use. Check both:
- `curl ifconfig.me` (may differ from actual connection IP)
- The IP in Snowflake's error message (the actual IP Snowflake sees)

The VPC CIDR in the policy is the safety net — as long as you have an EC2 inside
the VPC, you can always recover from a lockout.

---

## Task 5.3: Enforcement Demonstration ✅

### Test: Remove Operator IPs → Verify Blocked

From inside the VPC (EC2), changed the policy to only allow VPC CIDR + a fake IP:

```sql
USE ROLE ACCOUNTADMIN;
ALTER NETWORK POLICY PRIVATELINK_ACCESS_POLICY
  SET ALLOWED_IP_LIST=('10.0.0.0/16','192.0.2.1/32');
```

**Result from browser:**
- `https://BTQJUPQ-DMB62145.snowflakecomputing.com` → Blocked ✅
  - Error: "Incoming request with IP/Token 102.203.137.234 is not allowed"
- `https://app.snowflake.com/BTQJUPQ/DMB62145` → Also blocked ✅
  - Error: "Incoming request with IP/Token 102.208.164.205 is not allowed"

### Test: Restore Operator IPs → Verify Access

From inside the VPC (EC2), restored both IPs:

```sql
ALTER NETWORK POLICY PRIVATELINK_ACCESS_POLICY
  SET ALLOWED_IP_LIST=('10.0.0.0/16','102.208.164.205/32','102.203.137.234/32');
```

**Result:** Both browser URLs accessible again ✅

### Synced Terraform State

After manual SQL changes, re-ran Terraform to sync state:

```bash
terraform apply -var='operator_ip=["102.208.164.205/32","102.203.137.234/32"]'
# Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

---

## Task 5.4: Snowflake Safety Mechanism ✅

Discovered that Snowflake **prevents self-lockout** when modifying a policy via its API:

```
Error: 098506 (22023): Changes cannot be applied to the network policy
PRIVATELINK_ACCESS_POLICY because current IP address/token 102.208.164.205
is not allowed in it.
```

This means:
- You **cannot** remove your own IP from a policy via Terraform/API if it would lock you out
- You **can** modify the policy from inside the VPC (different source IP, VPC CIDR always allowed)
- The safety check only applies to the connection making the change — not to other connections

This is why the enforcement demo had to be run from the EC2 inside the VPC.

---

## Snowflake URL Behavior

Two different Snowsight URL formats behave differently with network policies:

| URL | Format | Network Policy Enforced? |
|-----|--------|------------------------|
| `https://app.snowflake.com/BTQJUPQ/DMB62145` | Global platform URL | Yes (after login attempt) |
| `https://BTQJUPQ-DMB62145.snowflakecomputing.com` | Direct account URL | Yes (immediately) |

Both are blocked when the source IP is not in the allowed list, but the global URL
may load the initial page before enforcing the policy on authentication.

---

## Cost Estimate — Phase 5

### Phase 5 Resources

| Resource | Monthly Cost |
|----------|-------------|
| Snowflake network policy | $0.00 (free) |
| Snowflake account parameter | $0.00 (free) |
| **Phase 5 Total** | **$0.00/month** |

### Cumulative Cost

| Phase | Monthly Cost | Cumulative |
|-------|-------------|-----------|
| Phase 0 (IAM) | $0.01 | $0.01 |
| Phase 1 (Networking) | $36.55 | $36.56 |
| Phase 2 (PrivateLink) | $22.45 | $59.01 |
| Phase 3 (Linux EC2, running) | $11.88 | $70.89 |
| Phase 4 (Windows EC2, running) | $27.07 | $97.96 |
| Phase 5 (Network Policy) | $0.00 | **$97.96/month** |

### Steady-State Cost (after destroying test EC2s)

| Phase | Monthly Cost | Cumulative |
|-------|-------------|-----------|
| Phase 0 (IAM) | $0.01 | $0.01 |
| Phase 1 (Networking) | $36.55 | $36.56 |
| Phase 2 (PrivateLink) | $22.45 | $59.01 |
| Phase 5 (Network Policy) | $0.00 | **$59.01/month** |

The steady-state cost after destroying test instances is **~$59/month** (NAT + VPCE).

---

## Lessons Learned

1. **`allowed_ip_list` is simpler than network rules.** Network rules require a
   user-created database and schema. For straightforward IP allowlisting,
   `allowed_ip_list` directly on the policy is cleaner and has no dependencies.

2. **Your outbound IP may differ between tools.** `curl ifconfig.me` reports one IP,
   but your browser/Terraform may exit through a different IP (CGNAT, load balancing).
   Always check the IP in Snowflake's error message — that's what they actually see.

3. **`operator_ip` should be a list, not a string.** Multiple IPs are common
   (different exit gateways for different tools). Using `list(string)` avoids
   having to redesign when you discover a second IP.

4. **Snowflake prevents API-based self-lockout.** You cannot remove your own IP
   from a policy via the API/Terraform. To demonstrate enforcement, modify the
   policy from a different source (EC2 inside VPC).

5. **VPC CIDR is the ultimate safety net.** As long as the VPC CIDR is in the
   allowed list and you have an EC2 inside the VPC, you can always recover from
   any lockout scenario. Never remove the VPC CIDR from the policy.

6. **Sync Terraform after manual SQL changes.** If you modify the policy via
   `ALTER NETWORK POLICY` from SnowSQL, re-run `terraform apply` to sync state.
   Otherwise Terraform will show drift on the next plan.

---

## Pending

- [ ] Commit and push Phase 5 changes
- [ ] Destroy test EC2 instances (save ~$38.95/month)
- [ ] Final documentation and project wrap-up
