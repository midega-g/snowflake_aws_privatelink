# Troubleshooting — Snowflake AWS PrivateLink

Common issues encountered during implementation and their resolutions.

---

## SCP Blocks Operations in New Region

**Symptom:**
```
UnauthorizedOperation: You are not authorized to perform this operation.
... explicit deny in a service control policy
```

**Cause:** The `DenyNonAllowedRegions` SCP doesn't include the target region.

**Fix:**
```bash
cd ~/Desktop/Learning/aws-org-infra/01_org_setup/02_identity/scps
# Update terraform.tfvars — this takes precedence over variables.tf defaults
# allowed_regions = ["af-south-1", "us-east-1", "us-west-2"]
terraform apply
```

**Gotcha:** If you only update `variables.tf` but `terraform.tfvars` exists with the
same key, the tfvars value wins. Always check both files.

---

## STS AssumeRole Fails with SignatureDoesNotMatch

**Symptom:**
```
SignatureDoesNotMatch: Credential should be scoped to a valid region.
```

**Cause:** Using the global STS endpoint (`sts.amazonaws.com`) but `sts_region` is set
to something other than `us-east-1`.

**Fix:** In provider.tf:
```hcl
sts_region = "us-east-1"  # Required for global endpoint request signing

endpoints {
  sts = "https://sts.amazonaws.com"
}
```

**Why this happens:** Opt-in regions (af-south-1, me-south-1, ap-east-1, etc.) have
regional STS endpoints that reject cross-region AssumeRole. The workaround is to route
through the global endpoint, which requires `us-east-1` for request signing.

**When this does NOT apply:** If your credentials and resources are both in standard
regions (us-east-1, us-west-2, eu-west-1, etc.), you don't need the `sts_region` or
`endpoints` blocks at all.

---

## GetFederationToken Fails from Assumed Role

**Symptom:**
```
AccessDenied: User: arn:aws:sts::...:assumed-role/... is not authorized to perform:
sts:GetFederationToken
```

**Cause:** AWS does not allow `GetFederationToken` from assumed-role sessions. This is
a hard AWS limitation — no IAM policy can override it.

**Fix:** Use a dedicated IAM user in the target account. The `02_privatelink` workspace
creates `snowflake-privatelink-auth` with only `sts:GetFederationToken` permission.
The scripts read its credentials from `terraform output`.

---

## Windows EC2 RDP Port 3389 Not Responding

**Symptom:**
```
freerdp_tcp_connect: ERRCONNECT_CONNECT_FAILED [0x00020006]
failed to connect to <ip>
```

**Cause:** Windows Server 2022 Full Base AMI does not have RDP enabled on first boot.
The Terminal Services listener is disabled by default.

**Fix:** Add PowerShell user_data:
```hcl
user_data = <<-EOF
  <powershell>
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
  Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
  Set-Service -Name "TermService" -StartupType Automatic
  Start-Service -Name "TermService"
  </powershell>
EOF
```

**Debugging checklist:**
1. Instance running? `terraform state show aws_instance.windows_test | grep instance_state`
2. Security group has your IP? `terraform state show aws_security_group_rule.rdp_inbound`
3. Port open externally? `timeout 10 bash -c "echo > /dev/tcp/<ip>/3389"`
4. Port open internally? SSH into Linux EC2 → test Windows private IP
5. AMI correct? Should be `Windows_Server-2022-English-Full-Base-*` not ECS-optimized

---

## Network Policy Locks You Out

**Symptom:**
```
390422 (08004): Incoming request with IP/Token <ip> is not allowed to access Snowflake.
```

**Cause:** Your IP is not in the network policy's allowed list.

**Fix — Option 1: From inside VPC (most reliable):**
```bash
# If EC2 doesn't exist, create it first:
cd terraform/03_ec2_test
terraform apply -var="operator_ip=$(curl -s ifconfig.me)/32"

# SSH in and unset the policy
ssh -i ./snowflake-privatelink-test-key.pem ec2-user@<linux_ec2_ip>
SNOWSQL_PWD='<password>' ~/bin/snowsql \
  -a qbb21532.us-west-2.privatelink -u SNOWLEARN \
  -o friendly=false \
  -q "USE ROLE ACCOUNTADMIN; ALTER ACCOUNT UNSET NETWORK_POLICY;"
```

The VPC CIDR (`10.0.0.0/16`) is always in the policy — EC2 inside the VPC can always
connect.

**Fix — Option 2: Via Snowflake web UI (may not work with all policies):**

Try logging in at `https://app.snowflake.com/<ORG>/<ACCOUNT>` — this global URL
sometimes bypasses the policy for the initial login. If you can access a worksheet:

```sql
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT UNSET NETWORK_POLICY;
-- or to completely remove:
DROP NETWORK POLICY PRIVATELINK_ACCESS_POLICY;
```

**Note:** This does NOT always work. If the policy blocks `app.snowflake.com` traffic
too (which it did in our testing), Option 1 (EC2 inside VPC) is the only reliable
recovery path.

**Fix — Option 3: Terraform destroy (if Terraform itself isn't blocked):**
```bash
cd terraform/04_network_policy
terraform destroy -var='operator_ip=["0.0.0.0/32"]'
```

This fails if Terraform's connection to Snowflake is also blocked — use Option 1 first.

**SnowSQL note:** After reinstalling SnowSQL (e.g., on a fresh EC2), if you see
"SnowSQL was not found in ~/.snowsql", reinstall it cleanly:
```bash
rm -rf ~/bin/snowsql ~/.snowsql
curl -s -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.5/linux_x86_64/snowsql-1.5.0-linux_x86_64.bash
SNOWSQL_DEST=~/bin SNOWSQL_LOGIN_SHELL=~/.bashrc bash snowsql-1.5.0-linux_x86_64.bash
```

---

## Multiple Exit IPs (Browser vs CLI)

**Symptom:** Policy allows your IP from `curl ifconfig.me` but browser is blocked with
a different IP.

**Cause:** Browser extensions (ad blockers, VPN extensions like uBlock Origin Lite /
Windscribe) route browser traffic through a proxy with a different exit IP.

**Fix:** Add both IPs to the policy:
```bash
cd terraform/04_network_policy
terraform apply -var='operator_ip=["<cli_ip>/32","<browser_ip>/32"]'
```

To find the browser IP: check the Snowflake error message — it shows the actual IP
it received.

---

## Snowflake Prevents Self-Lockout via API

**Symptom:**
```
098506 (22023): Changes cannot be applied to the network policy because current
IP address/token <ip> is not allowed in it.
```

**Cause:** Snowflake's safety mechanism prevents you from removing your own IP from a
policy via the API/Terraform.

**Workaround:** Modify the policy from a different source IP (e.g., EC2 inside VPC)
using `ALTER NETWORK POLICY` SQL.

---

## Terraform Output Returns Empty (Scripts Fail)

**Symptom:** `authorize-privatelink.sh` or `verify-privatelink.sh` fails silently or
shows empty values.

**Cause:** The scripts call `terraform output` which reads from S3 backend. Without
`AWS_PROFILE` set, it can't authenticate to S3.

**Fix:** Always run scripts with the profile:
```bash
export AWS_PROFILE=org_mgmt_epf
./scripts/authorize-privatelink.sh
```

---

## SnowSQL --private-host-suffix Not Found

**Symptom:**
```
no such option: --private-host-suffix
```

**Cause:** This flag doesn't exist in SnowSQL 1.5.0.

**Fix:** Use the PrivateLink account format directly:
```bash
snowsql -a <account_locator>.<region>.privatelink -u <user>
# Example:
snowsql -a qbb21532.us-west-2.privatelink -u SNOWLEARN
```

SnowSQL appends `.snowflakecomputing.com` automatically.

---

## Snowflake Provider Attribute Names Don't Match Docs

**Symptom:** Terraform validation errors like:
```
This object has no argument, nested block, or exported attribute named "privatelink_account_url"
```

**Cause:** The Terraform data source uses different attribute names than Snowflake's SQL
function output or documentation.

**Fix:** Use `terraform providers schema -json` to discover actual attribute names:
```bash
terraform providers schema -json | jq \
  '.provider_schemas["registry.terraform.io/snowflakedb/snowflake"].data_source_schemas["snowflake_system_get_privatelink_config"].block.attributes | to_entries[] | .key'
```

Common mappings:
| Docs / SQL output | Terraform attribute |
|-------------------|-------------------|
| `privatelink-account-url` | `account_url` |
| `privatelink-ocsp-url` | `ocsp_url` |
| `privatelink-vpce-id` | `aws_vpce_id` |
| `regionless-snowsight-privatelink-url` | `regionless_snowsight_url` |

---

## xfreerdp Certificate Warning

**Symptom:**
```
WARNING: CERTIFICATE NAME MISMATCH!
CN = EC2AMAZ-E1UACB9
```

**Cause:** Normal — EC2 Windows instances use a self-signed certificate with the
internal hostname, not the public IP.

**Fix:** Type `Y` to trust the certificate. This is expected for EC2 instances.

---

## xfreerdp Disconnected by Another Connection

**Symptom:**
```
ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION (0x00000005)
```

**Cause:** Another RDP client connected to the same instance. Windows Server allows
only one interactive Administrator session by default.

**Fix:** Not an error — just use one RDP client at a time.
