# Implementation Log — Phase 4: Snowsight & Full Connectivity Validation

## Date: 2026-07-19

---

## Goal

Validate Snowflake PrivateLink works for **all access methods** — CLI (SnowSQL),
programmatic (port tests), and browser (Snowsight). This phase adds Snowsight CNAME
records to DNS and a Windows EC2 instance for browser-based testing via RDP.

---

## Task 4.1: Snowsight CNAME Records ✅

### Background

Snowflake's `SYSTEM$GET_PRIVATELINK_CONFIG` returns multiple URLs that need DNS
resolution inside the VPC. Phase 2 created CNAMEs for the account URL and OCSP URL.
This task adds the Snowsight URLs so the web UI works from inside the VPC.

### Records Added (in `02_privatelink/dns.tf`)

| Record | URL | Purpose |
|--------|-----|---------|
| Snowsight regionless | `app-btqjupq-dmb62145.privatelink.snowflakecomputing.com` | Browser access (org-specific) |
| Snowsight regional | `app.us-west-2.privatelink.snowflakecomputing.com` | Browser access (region-specific) |
| Regionless account | `btqjupq-dmb62145.privatelink.snowflakecomputing.com` | API/client access without region |
| Regionless OCSP | `ocsp.btqjupq-dmb62145.privatelink.snowflakecomputing.com` | Certificate validation (regionless) |

### Code Improvement: Locals for Readability

Refactored `dns.tf` to use locals instead of repeating the data source path:

```hcl
locals {
  pl_config = data.snowflake_system_get_privatelink_config.this
  vpce_dns  = aws_vpc_endpoint.snowflake.dns_entry[0].dns_name
}

# Each record now uses:
name    = local.pl_config.regionless_snowsight_url
records = [local.vpce_dns]
```

### Apply

```bash
export AWS_PROFILE=org_mgmt_epf
cd terraform/02_privatelink
terraform apply -auto-approve
# Plan: 4 to add, 0 to change, 0 to destroy.
# Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

### Verification (from Linux EC2)

```bash
# DNS resolution
nslookup app-btqjupq-dmb62145.privatelink.snowflakecomputing.com
# → Resolves to 3 private IPs (10.0.x.x)

# HTTP response
curl -sI https://app-btqjupq-dmb62145.privatelink.snowflakecomputing.com | head -5
# HTTP/2 200
# server: SF-LB
```

---

## Task 4.2: Windows EC2 for Snowsight (RDP) ✅

### Why a Separate Windows Instance

Snowsight is a browser-based UI. To access it from inside the VPC, you need a browser
running inside the VPC. Options considered:

| Approach | Verdict |
|----------|---------|
| Install XRDP + GNOME on Linux EC2 | Heavy, hacky, poor performance on t3.micro |
| Separate Windows EC2 | Native RDP, Edge pre-installed, clean separation of concerns |

A separate Windows instance is more realistic (prod would have separate bastion hosts
per OS) and simpler to operate.

### Resources Created (in `03_ec2_test/windows.tf`)

| Resource | Details |
|----------|---------|
| `data.aws_ami.windows_2022` | Windows_Server-2022-English-Full-Base (latest) |
| `aws_security_group.windows_test` | RDP (3389) from operator IP only + all outbound |
| `aws_instance.windows_test` | t3.small, public subnet us-west-2a, user_data enables RDP |

---

## Task 4.3: RDP Debugging ✅

### Issue: Port 3389 Not Responding After Boot

**Symptom:**

```
$ xfreerdp /v:52.41.197.206 /u:Administrator /p:'...'
[ERROR][com.freerdp.core] - freerdp_tcp_connect: ERRCONNECT_CONNECT_FAILED [0x00020006]
[ERROR][com.freerdp.core] - failed to connect to 52.41.197.206
```

Remmina also failed: "lost connection to RDP server."

**Debugging steps:**

```bash
# 1. Verify instance is running
terraform state show aws_instance.windows_test | grep "instance_state"
# instance_state = "running"

# 2. Verify security group has correct IP
terraform state show aws_security_group_rule.rdp_inbound | grep -A2 "cidr"
# cidr_blocks = ["102.208.164.205/32"]

# 3. Verify current IP matches
curl -s ifconfig.me
# 102.208.164.205  ← matches

# 4. Test port externally
timeout 10 bash -c "echo > /dev/tcp/52.41.197.206/3389" && echo "OPEN" || echo "CLOSED"
# CLOSED

# 5. Test port internally (from Linux EC2 to Windows private IP)
ssh ec2-user@<linux_ip> "timeout 5 bash -c 'echo > /dev/tcp/10.0.1.97/3389' && echo OPEN || echo CLOSED"
# CLOSED — confirms it's not a SG/NACL issue but Windows-side

# 6. Verify AMI is correct (not ECS-optimized or stripped variant)
terraform state show 'data.aws_ami.windows_2022' | grep "name "
# name = "Windows_Server-2022-English-Full-Base-2026.07.15"  ← correct

# 7. Verify instance type is adequate
# t3.small (2 vCPU, 2 GB) — sufficient for Windows + RDP

# 8. Confirmed: Linux EC2 SSH works on same subnet → routing/NACLs are fine
ssh ec2-user@35.91.103.104 "echo SSH_OK"
# SSH_OK
```

**What each test ruled out:**
- Steps 1-3: Instance is running, SG is correct, IP matches → not an infrastructure issue
- Step 4: Port closed from outside → not just a client problem
- Step 5: Port closed from inside VPC too → it's the Windows instance itself, not network
- Step 6: AMI is "Full Base" → not a stripped/ECS variant
- Step 7: t3.small is adequate for Windows + RDP
- Step 8: Linux SSH works on same subnet → VPC routing, NACLs, IGW all fine

**Root cause:** Windows Server 2022 Full Base AMI does not have RDP enabled on first
boot by default (despite the "Full" label). The Terminal Services listener is disabled
until explicitly configured via registry or Group Policy.

**Fix:** Added PowerShell user_data to enable RDP on boot:

```hcl
user_data = <<-EOF
  <powershell>
  # Enable Remote Desktop
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0

  # Enable Windows Firewall rule for RDP
  Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

  # Ensure RDP service is running
  Set-Service -Name "TermService" -StartupType Automatic
  Start-Service -Name "TermService"
  </powershell>
EOF
```

**After recreating** with `terraform apply -replace=aws_instance.windows_test`:

```bash
timeout 10 bash -c "echo > /dev/tcp/35.92.226.165/3389" && echo "OPEN" || echo "CLOSED"
# PORT OPEN ✓
```

---

## Task 4.4: Connecting via RDP ✅

### Option 1: AWS Console (easiest for first-time password retrieval)

1. Go to **EC2 → Instances** → select the Windows instance
2. Click **Connect** → **RDP client** tab
3. Click **Download remote desktop file** (`.rdp` file for your RDP client)
4. Click **Get password** → Upload `snowflake-privatelink-test-key.pem` or paste its content
5. AWS decrypts and shows the Administrator password
6. Open the `.rdp` file with Remmina or any RDP client

The private key is `snowflake-privatelink-test-key.pem` — the same key pair shared
between both Linux and Windows instances (`aws_key_pair.test`).

### Option 2: Terraform + CLI (no console needed)

```bash
# Decrypt the password (requires AWS_PROFILE set for state access)
cd terraform/03_ec2_test
terraform output -raw windows_admin_password | base64 -d | openssl pkeyutl -decrypt -inkey ./snowflake-privatelink-test-key.pem

# Connect with xfreerdp
xfreerdp /v:<windows_public_ip> /u:Administrator /p:'<decrypted_password>' /size:1920x1080
```

### Option 3: Remmina GUI

1. Open Remmina → New connection
2. Protocol: RDP
3. Server: `<windows_public_ip>:3389`
4. Username: `Administrator`
5. Password: (from decrypt command or console)
6. Connect

### Connection Notes (xfreerdp)

On first connection, xfreerdp shows certificate warnings — these are **expected**:

```
[WARN][com.freerdp.crypto] - Certificate verification failure 'self-signed certificate (18)'
[WARN][com.freerdp.crypto] - CN = EC2AMAZ-E1UACB9
[ERROR][com.freerdp.crypto] - WARNING: CERTIFICATE NAME MISMATCH!
```

This is normal — EC2 Windows instances use a self-signed certificate with the internal
hostname (`EC2AMAZ-xxxxx`), not the public IP. Type `Y` to trust and proceed.

**Disconnected by another connection:**

```
[INFO][com.freerdp.core] - ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION (0x00000005):
Another user connected to the server, forcing the disconnection of the current connection.
```

This means another RDP client (e.g., Remmina) connected to the same instance, which
disconnects the first session. Windows Server allows only one interactive Administrator
session by default. This is expected — not an error.

---

## Task 4.5: Snowsight Browser Test ✅

After connecting via RDP:

1. Open **Microsoft Edge** (pre-installed on Windows Server 2022)
2. Navigate to: `https://app-btqjupq-dmb62145.privatelink.snowflakecomputing.com`
3. Snowflake login page loads ✅
4. Login with Snowflake credentials → Snowsight dashboard accessible ✅

All browser traffic resolves via:
```
Edge browser
  → Windows DNS resolver
  → VPC DNS (10.0.0.2)
  → Route53 private hosted zone
  → CNAME → VPCE ENI private IPs
  → PrivateLink to Snowflake
```

No public internet involved.

---

## Full Test Summary

| Test | Method | Result |
|------|--------|--------|
| DNS resolution | `nslookup` from Linux EC2 | ✅ Resolves to 3 private IPs (VPCE ENIs) |
| Port 443 (HTTPS) | `/dev/tcp` from Linux EC2 | ✅ Connected (all 3 AZs) |
| Port 80 (OCSP) | `/dev/tcp` from Linux EC2 | ✅ Connected (all 3 AZs) |
| SnowSQL query | `snowsql` from Linux EC2 | ✅ Returns QBB21532 / AWS_US_WEST_2 |
| Snowsight DNS | `nslookup` from Linux EC2 | ✅ Resolves to private IPs |
| Snowsight HTTP | `curl -sI` from Linux EC2 | ✅ HTTP/2 200 from SF-LB |
| Snowsight browser | Edge via RDP into Windows EC2 | ✅ Login page loads, dashboard accessible |
| Traffic path | All resolved IPs in 10.0.x.x | ✅ No public IPs involved |

**PrivateLink is fully operational — CLI, programmatic, and browser access all validated.**

---

## Cost Estimate — Phase 4

### Phase 4 Resources (monthly, while running)

| Resource | Unit Price | Quantity | Monthly Cost |
|----------|-----------|----------|-------------|
| EC2 t3.small Windows (on-demand) | $0.0288/hour | 730 hrs | $21.02 |
| EBS gp3 root volume Windows (30 GB) | $0.08/GB/month | 30 GB | $2.40 |
| Public IPv4 address | $0.005/hour | 730 hrs | $3.65 |
| Security Group | Free | 1 | $0.00 |
| Route53 CNAME records (4 new) | Included in zone cost | 4 | $0.00 |
| **Phase 4 Total (running)** | | | **~$27.07/month** |

### Cost When Destroyed

All Phase 4 EC2 resources: $0.00 (fully destroyed).
Route53 records persist (negligible — included in the $0.50/month zone from Phase 2).

### Cumulative Cost

| Phase | Monthly Cost | Cumulative |
|-------|-------------|-----------|
| Phase 0 (IAM) | $0.01 | $0.01 |
| Phase 1 (Networking) | $36.55 | $36.56 |
| Phase 2 (PrivateLink) | $22.45 | $59.01 |
| Phase 3 (Linux EC2, running) | $11.88 | $70.89 |
| Phase 4 (Windows EC2, running) | $27.07 | **$97.96/month** |

### Recommendation

Destroy both test EC2 instances after validation is complete:
```bash
cd terraform/03_ec2_test
terraform destroy -var="operator_ip=$(curl -s ifconfig.me)/32"
```

This removes ~$38.95/month (Phase 3 + Phase 4 EC2s). Both instances can be recreated
at any time with `terraform apply` — user_data handles all software installation and
configuration automatically. The Route53 CNAME records remain (part of `02_privatelink`).

---

## Lessons Learned

1. **Windows Server 2022 AMI requires explicit RDP enablement.** Despite being the
   "Full Base" image, RDP is not listening on first boot. Always include PowerShell
   user_data to set `fDenyTSConnections = 0`, enable the firewall rule, and start
   the TermService.

2. **Debug from inside the VPC first.** Testing port 3389 from the Linux EC2
   (inside the VPC, bypassing external network) confirmed the issue was Windows-side,
   not SG/NACL/routing. This avoids wasting time on network troubleshooting.

3. **`-replace` flag for user_data changes.** Since user_data only runs on first boot,
   changing it requires instance recreation. Use
   `terraform apply -replace=aws_instance.windows_test` instead of destroy+apply.

4. **xfreerdp certificate warnings are normal.** EC2 Windows instances use self-signed
   certs with internal hostnames. Accept the warning on first connection.

5. **One RDP session per user.** Connecting from a second client disconnects the first.
   If you see `DISCONNECTED_BY_OTHER_CONNECTION`, it means another client took over —
   not an infrastructure failure.

---

## Pending

- [ ] Commit and push Phase 4 changes
- [ ] **Phase 5:** Network policy (VPC CIDR + operator IP, demonstrate lockdown)
- [ ] Destroy both EC2 instances after all testing complete
