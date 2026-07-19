# Implementation Log — Phase 3: EC2 Test Instance

## Date: 2026-07-19

---

## Goal

Spin up an ephemeral EC2 instance in a public subnet (us-west-2a) to validate
Snowflake PrivateLink connectivity — DNS resolution, port 443/80 reachability
across all 3 AZs, and optionally SnowSQL connection via the private endpoint.

---

## Task 3.1: Create Terraform Files ✅

### Files Created

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform >= 1.10.0 < 2.0.0, AWS ~> 6.38, TLS ~> 4.0, Local ~> 2.5 |
| `backend.tf` | S3 remote state (`projects/snowflake-privatelink/ec2-test/terraform.tfstate`) |
| `data.tf` | Remote state lookups (sandbox, networking, privatelink) + AMI data source |
| `provider.tf` | Cross-account assume role + STS workaround + default_tags |
| `variables.tf` | 6 variables (region, project_name, state_bucket, state_region, operator_ip, instance_type) |
| `main.tf` | TLS key pair, EC2 security group, EC2 instance with user_data |
| `outputs.tf` | instance_id, public_ip, private_key_path, ssh_command, test_command |

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| `tls_private_key` resource | Self-contained, idempotent — no manual key generation needed |
| `local_file` for .pem | Writes key locally with 0400 perms; gitignored via `*.pem` |
| Public subnet placement | Needs SSH access from operator's machine; PrivateLink still works (DNS resolves via Route53 private zone associated with VPC) |
| `operator_ip` as required variable | No default — forces explicit IP to avoid open SSH |
| User data: `bind-utils telnet nc` | Provides `nslookup`, `telnet`, and `nc` for connectivity testing |
| Instance in subnet [0] (us-west-2a) | Sufficient for testing; tests connect to ENIs in all 3 AZs |

---

## Task 3.2: Validate ✅

```bash
export AWS_PROFILE=org_mgmt_epf
cd terraform/03_ec2_test

terraform init
# Terraform has been successfully initialized!

terraform validate
# Success! The configuration is valid.

terraform plan -var="operator_ip=$(curl -s ifconfig.me)/32"
# Plan: 7 to add, 0 to change, 0 to destroy.
```

---

## Task 3.3: Apply ✅

```bash
terraform apply -auto-approve -var="operator_ip=$(curl -s ifconfig.me)/32"
# Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

### Resources Created (7)

| Resource | Type |
|----------|------|
| TLS Private Key (RSA 4096) | `tls_private_key` |
| Key Pair | `aws_key_pair` |
| Private Key File (.pem) | `local_file` |
| Security Group | `aws_security_group` |
| SG Rule: SSH inbound | `aws_security_group_rule` |
| SG Rule: All outbound | `aws_security_group_rule` |
| EC2 Instance (t3.micro, AL2023) | `aws_instance` |

### Outputs

```
instance_id      = (from terraform output)
public_ip        = (from terraform output)
private_key_path = "./snowflake-privatelink-test-key.pem"
ssh_command      = "ssh -i ./snowflake-privatelink-test-key.pem ec2-user@<public_ip>"
test_command     = "nslookup qbb21532.us-west-2.privatelink.snowflakecomputing.com"
```

---

## Task 3.4: Connectivity Validation ✅

### Test 1: DNS Resolution

```bash
ssh -i ./snowflake-privatelink-test-key.pem ec2-user@<public_ip>

nslookup qbb21532.us-west-2.privatelink.snowflakecomputing.com
```

**Result:**

```
Server:         10.0.0.2
Address:        10.0.0.2#53

Non-authoritative answer:
qbb21532.us-west-2.privatelink.snowflakecomputing.com
    canonical name = vpce-0799456a9318ea683-s0r90mjk.vpce-svc-0c046e929777343f1.us-west-2.vpce.amazonaws.com.
Name:   vpce-...us-west-2.vpce.amazonaws.com
Address: 10.0.60.40
Name:   vpce-...us-west-2.vpce.amazonaws.com
Address: 10.0.25.115
Name:   vpce-...us-west-2.vpce.amazonaws.com
Address: 10.0.35.179
```

**Analysis:**
- DNS resolves via the VPC DNS resolver (`10.0.0.2`)
- CNAME correctly points to the VPCE regional DNS name
- Returns 3 private IPs — one per AZ (ENI in each private subnet)
- All IPs are within VPC CIDR `10.0.0.0/16` — confirms traffic stays private

### Test 2: Port 443 (HTTPS) — All 3 AZs

| Endpoint IP | AZ | Result |
|------------|-----|--------|
| 10.0.60.40 | us-west-2c | CONNECTED ✓ |
| 10.0.25.115 | us-west-2a | CONNECTED ✓ |
| 10.0.35.179 | us-west-2b | CONNECTED ✓ |

### Test 3: Port 80 (OCSP) — All 3 AZs

| Endpoint IP | AZ | Result |
|------------|-----|--------|
| 10.0.60.40 | us-west-2c | CONNECTED ✓ |
| 10.0.25.115 | us-west-2a | CONNECTED ✓ |
| 10.0.35.179 | us-west-2b | CONNECTED ✓ |

### Summary

| Test | Status |
|------|--------|
| DNS resolves to private IPs | ✅ |
| CNAME → VPCE DNS name | ✅ |
| Port 443 all 3 AZs | ✅ |
| Port 80 all 3 AZs | ✅ |
| Traffic stays within VPC (no public IPs) | ✅ |

---

## How Connectivity Works (End-to-End)

```
EC2 (public subnet, us-west-2a)
  → nslookup qbb21532.us-west-2.privatelink.snowflakecomputing.com
  → VPC DNS resolver (10.0.0.2) checks Route53 private hosted zone
  → CNAME → vpce-xxx.vpce-svc-xxx.us-west-2.vpce.amazonaws.com
  → Resolves to 3 private IPs (VPCE ENIs in private subnets)
  → TCP connection to port 443 on ENI
  → AWS PrivateLink forwards to Snowflake's VPC
  → Snowflake responds
```

The EC2 instance is in a **public** subnet but the PrivateLink traffic flows over
**private** IPs within the VPC. The public subnet placement is only for SSH access
from the operator — PrivateLink connectivity works from any subnet in the VPC.

---

## Task 3.5: SnowSQL Connectivity Test ✅

### Installing SnowSQL

SnowSQL 1.5.0 was installed on the EC2 instance. Requires `unzip` as a dependency.

```bash
sudo dnf install -y unzip
curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.5/linux_x86_64/snowsql-1.5.0-linux_x86_64.bash
SNOWSQL_DEST=~/bin SNOWSQL_LOGIN_SHELL=~/.bashrc bash snowsql-1.5.0-linux_x86_64.bash
```

### Connection Command

The PrivateLink account identifier format is `<account_locator>.<region>.privatelink`.
SnowSQL appends `.snowflakecomputing.com` automatically.

```bash
~/bin/snowsql -a qbb21532.us-west-2.privatelink -u SNOWLEARN -q "SELECT CURRENT_ACCOUNT(), CURRENT_REGION();"
```

### Result

```
Password:
* SnowSQL * v1.5.0
Type SQL statements or !help
+-------------------+------------------+
| CURRENT_ACCOUNT() | CURRENT_REGION() |
|-------------------+------------------|
| QBB21532          | AWS_US_WEST_2    |
+-------------------+------------------+
1 Row(s) produced. Time Elapsed: 0.188s
Goodbye!
```

**Confirms:** Full end-to-end PrivateLink connectivity — DNS resolution, TCP connection,
TLS handshake, and Snowflake query execution all via private endpoint.

### SnowSQL Configuration Approaches

Three options for configuring SnowSQL on the test instance, with tradeoffs:

| Approach | Survives stop/start? | Survives destroy/recreate? | Setup effort |
|----------|---------------------|---------------------------|-------------|
| **Manual command** (`snowsql -a ... -u ...`) | N/A (typed each time) | N/A | None |
| **Config on EBS** (`~/.snowflake/connections.toml`) | ✅ Yes | ❌ No (volume deleted) | One-time manual |
| **user_data** (written on first boot) | ✅ Yes | ✅ Yes (re-created automatically) | In Terraform code |

**Recommendation per scenario:**

- **One-off testing:** Manual command. Simplest, no config to manage.
- **Repeated testing (stop/start):** Config on EBS is fine — persists across reboots.
- **Destroy/recreate cycles:** user_data is best — config is recreated automatically
  on every fresh instance. This is what's implemented.

### user_data Implementation

The EC2 user_data now includes:

```bash
#!/bin/bash
dnf install -y bind-utils telnet nc unzip

# Install SnowSQL 1.5.0
cd /tmp
curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.5/linux_x86_64/snowsql-1.5.0-linux_x86_64.bash
SNOWSQL_DEST=/home/ec2-user/bin SNOWSQL_LOGIN_SHELL=/home/ec2-user/.bashrc bash snowsql-1.5.0-linux_x86_64.bash

# SnowSQL config for PrivateLink (no password stored)
mkdir -p /home/ec2-user/.snowflake
cat > /home/ec2-user/.snowflake/connections.toml << 'TOML'
[default]
account = "qbb21532.us-west-2.privatelink"
user = "SNOWLEARN"
TOML
chown -R ec2-user:ec2-user /home/ec2-user/.snowflake /home/ec2-user/bin
```

**Security note:** No password is stored in user_data or config. The user is prompted
for password at runtime. Account and username are not sensitive (visible in Snowflake URL).

**user_data timing:** Only runs on **first boot** of a new instance. Changing user_data
on an existing instance updates the Terraform state but does NOT re-run on the live
instance. To apply new user_data, the instance must be destroyed and recreated
(`terraform destroy` then `terraform apply`).

---

## Full Test Summary

| Test | Method | Result |
|------|--------|--------|
| DNS resolution | `nslookup` | ✅ Resolves to 3 private IPs (VPCE ENIs) |
| Port 443 (HTTPS) | `/dev/tcp` | ✅ Connected (all 3 AZs) |
| Port 80 (OCSP) | `/dev/tcp` | ✅ Connected (all 3 AZs) |
| SnowSQL query | `snowsql -a ... -q ...` | ✅ Returns QBB21532 / AWS_US_WEST_2 |
| Traffic path | Private IPs in 10.0.x.x | ✅ No public IPs involved |

**PrivateLink is fully operational.**

---

## Cost Estimate — Phase 3

### Phase 3 Resources (monthly, while running)

| Resource | Unit Price | Quantity | Monthly Cost |
|----------|-----------|----------|-------------|
| EC2 t3.micro (on-demand) | $0.0104/hour | 730 hrs | $7.59 |
| EBS gp3 root volume (8 GB) | $0.08/GB/month | 8 GB | $0.64 |
| Public IPv4 address | $0.005/hour | 730 hrs | $3.65 |
| Key Pair | Free | 1 | $0.00 |
| Security Group | Free | 1 | $0.00 |
| **Phase 3 Total (running)** | | | **~$11.88/month** |

### Cost When Stopped

| Resource | Monthly Cost |
|----------|-------------|
| EBS volume (persists) | $0.64 |
| Public IP (released) | $0.00 |
| EC2 compute (stopped) | $0.00 |
| **Phase 3 Total (stopped)** | **~$0.64/month** |

### Cumulative Cost (All Phases, EC2 running)

| Phase | Monthly Cost | Cumulative |
|-------|-------------|-----------|
| Phase 0 (IAM) | $0.01 | $0.01 |
| Phase 1 (Networking) | $36.55 | $36.56 |
| Phase 2 (PrivateLink) | $22.45 | $59.01 |
| Phase 3 (EC2, running) | $11.88 | **$70.89/month** |

### Recommendation

Destroy the EC2 instance after validation is complete (`terraform destroy` in
`03_ec2_test`). This removes ~$11.88/month. The instance can be recreated at
any time with `terraform apply` — the key pair and security group are recreated
fresh each time (user_data handles SnowSQL install and config automatically).

---

## Pending

- [ ] Stop or destroy EC2 after all tests pass
- [ ] Commit and push Phase 3 changes
- [ ] **Phase 5:** Network policy (block public access after validation)
