# Implementation Tasks — Snowflake AWS PrivateLink

## Phase 0: Project Setup

### Task 0.1: Create GitHub Repository
- [ ] Run `gh repo create snowflake_aws_privatelink --private` from `~/Desktop/Learning/`
- [ ] Clone into `~/Desktop/Learning/snowflake_aws_privatelink`
- [ ] Initialize with `.gitignore`, `.pre-commit-config.yaml`, `README.md`
- [ ] Create directory structure per design spec

### Task 0.2: Create IAM Role in aws-org-infra
- [ ] Create file `aws-org-infra/01_org_setup/03_security/01_management_iam/snowflake_privatelink_role.tf`
- [ ] Define `snowflake-privatelink-admin` IAM role with trust policy for existing admin user
- [ ] Define scoped IAM policy with permissions:
  - `sts:GetFederationToken`
  - `sts:AssumeRole` (sandbox account only)
  - `ec2:*Vpc*`, `ec2:*Subnet*`, `ec2:*SecurityGroup*`, `ec2:*Instance*`, `ec2:*KeyPair*`, `ec2:Describe*`
  - `ec2:*NetworkInterface*` (for VPC endpoint ENIs)
  - `route53:*` (private hosted zones only)
  - `s3:GetObject`, `s3:PutObject` on state bucket prefix `projects/snowflake-privatelink/*`
  - `s3:ListBucket` on state bucket
- [ ] `terraform plan` and `terraform apply` in management_iam workspace
- [ ] Verify role is assumable: `aws sts assume-role --role-arn <arn>`

### Task 0.3: Update OIDC Trust Policy (for CI/CD — can defer)
- [ ] Add `snowflake_aws_privatelink` repo to trusted subjects in `03_github_oidc`
- [ ] Plan and apply

---

## Phase 1: Networking (workspace: `terraform/01_networking`)

### Task 1.1: VPC and Subnets
- [ ] Create `aws_vpc.main` with CIDR `10.0.0.0/16`, DNS hostnames + support enabled
- [ ] Create 3 public subnets (one per AZ: us-west-2a, 2b, 2c)
- [ ] Create 3 private subnets (one per AZ)
- [ ] Tag all subnets with `Name`, `project:*` tags, and `network:tier` (public/private)

### Task 1.2: Gateways and NAT
- [ ] Create Internet Gateway, attach to VPC
- [ ] Create Elastic IP for NAT Gateway
- [ ] Create NAT Gateway in 1 AZ (us-west-2a public subnet)
- [ ] Tag with `Name` and project tags

### Task 1.3: Route Tables
- [ ] Public route table: 0.0.0.0/0 → Internet Gateway
- [ ] Private route table: 0.0.0.0/0 → NAT Gateway
- [ ] Associate public subnets with public route table
- [ ] Associate private subnets with private route table

### Task 1.4: Backend and Provider
- [ ] Configure S3 backend: key = `projects/snowflake-privatelink/networking/terraform.tfstate`
- [ ] Provider assumes `OrganizationAccountAccessRole` in sandbox account
- [ ] All resources tagged via `default_tags`

### Task 1.5: Outputs
- [ ] Output VPC ID, public subnet IDs, private subnet IDs, VPC CIDR, route table IDs

---

## Phase 2: PrivateLink (workspace: `terraform/02_privatelink`)

### Task 2.1: Snowflake PrivateLink Config Data Source
- [ ] Configure Snowflake provider with `profile = "default"` and `preview_features_enabled`
- [ ] Use `data.snowflake_system_get_privatelink_config.this` to retrieve:
  - `aws_vpce_id` (service name for the VPC endpoint)
  - `account_url`
  - `ocsp_url`

### Task 2.1a: Auth User (for federation token)
- [ ] Create IAM user `snowflake-privatelink-auth` in sandbox (path `/ephemeral/`)
- [ ] Inline policy: only `sts:GetFederationToken`
- [ ] Create access key (output as sensitive)
- [ ] Scripts read credentials from `terraform output` at runtime

### Task 2.2: Security Group
- [ ] Create `aws_security_group.snowflake_privatelink`
- [ ] Inbound rule: TCP port 443 from VPC CIDR (10.0.0.0/16)
- [ ] Inbound rule: TCP port 80 from VPC CIDR (OCSP cache)
- [ ] Outbound: allow all (default)
- [ ] Tag with `Name = snowflake-privatelink-endpoint-sg`

### Task 2.3: VPC Interface Endpoint (Snowflake)
- [ ] Create `aws_vpc_endpoint.snowflake` with type "Interface"
- [ ] `service_name` from Snowflake data source
- [ ] Place in all 3 private subnets
- [ ] Attach security group from Task 2.2
- [ ] `private_dns_enabled = false`
- [ ] Tag with `Name = snowflake-privatelink-endpoint`

### Task 2.4: S3 Gateway Endpoint
- [ ] Create `aws_vpc_endpoint.s3` with type "Gateway"
- [ ] Service name: `com.amazonaws.us-west-2.s3`
- [ ] Associate with private route tables
- [ ] Tag with `Name = snowflake-privatelink-s3-gateway`

### Task 2.5: Route53 Private Hosted Zone (Snowflake)
- [ ] Create zone: `privatelink.snowflakecomputing.com`
- [ ] Associate with the VPC
- [ ] CNAME record: `<account>.us-west-2` → VPCE regional DNS name
- [ ] CNAME record: `ocsp.<account>.us-west-2` → VPCE regional DNS name
- [ ] CNAME record: `regionless-snowsight-privatelink-url` → VPCE regional DNS name
- [ ] CNAME record: `snowsight-privatelink-url` → VPCE regional DNS name
- [ ] Tag zone with project tags

### Task 2.6: Route53 Private Hosted Zone (S3 Stage) — if needed
- [ ] Determine Snowflake internal S3 bucket URL from `SYSTEM$GET_PRIVATELINK_CONFIG`
- [ ] NOTE: With gateway endpoint + route table association, DNS resolution
      for S3 happens automatically. A separate hosted zone may NOT be needed
      for gateway endpoints (only for interface endpoints). Validate during testing.

### Task 2.7: Backend, Provider, Outputs
- [ ] S3 backend key: `projects/snowflake-privatelink/privatelink/terraform.tfstate`
- [ ] Read networking state via `terraform_remote_state`
- [ ] Output: VPCE ID, VPCE DNS names, hosted zone ID, security group ID

---

## Phase 3: EC2 Test Instance (workspace: `terraform/03_ec2_test`)

### Task 3.1: Key Pair
- [ ] Generate key pair locally or use `tls_private_key` resource
- [ ] Create `aws_key_pair.test`
- [ ] Store private key securely (not in git)

### Task 3.2: Security Group
- [ ] Create `aws_security_group.ec2_test`
- [ ] Inbound: SSH (port 22) from `var.operator_ip` only
- [ ] Outbound: all
- [ ] Tag with `Name = snowflake-privatelink-ec2-test-sg`

### Task 3.3: EC2 Instance
- [ ] Amazon Linux 2023 AMI (latest, use `data.aws_ami`)
- [ ] Instance type: `t3.micro`
- [ ] Place in public subnet (us-west-2a)
- [ ] Associate public IP
- [ ] Attach key pair and security group
- [ ] User data: install telnet, nslookup tools
- [ ] Tag with `Name = snowflake-privatelink-test`

### Task 3.4: Outputs
- [ ] Output: instance ID, public IP, SSH command

---

## Phase 4: Connectivity Validation

### Task 4.1: SSH and Test (Linux EC2)
- [ ] SSH into EC2 instance
- [ ] Run `nslookup <account>.us-west-2.privatelink.snowflakecomputing.com`
- [ ] Verify returned IPs match VPCE ENI private IPs
- [ ] Run `telnet <ip> 443` for each AZ — expect "Connected"
- [ ] Run `telnet <ip> 80` for each AZ — expect "Connected"
- [ ] Connect via SnowSQL: `snowsql -a <account>.us-west-2.privatelink -u <user>`
- [ ] Verify `CURRENT_REGION()` returns `AWS_US_WEST_2`

### Task 4.2: RDP and Test (Windows EC2)
- [ ] Create Windows EC2 (separate instance in same VPC/subnet)
- [ ] Security group: RDP (port 3389) from operator IP only + all outbound
- [ ] RDP into Windows instance
- [ ] Open browser → navigate to Snowsight privatelink URL
- [ ] Verify Snowflake login page loads and login works
- [ ] Screenshot as evidence for article

### Task 4.3: Demonstrate Lockdown
- [ ] From EC2 (inside VPC): `curl -I <snowsight-privatelink-url>` → HTTP 200
- [ ] From laptop (your IP allowed): Snowsight loads normally
- [ ] Remove your IP from network policy → laptop access blocked
- [ ] Re-add your IP → access restored
- [ ] Document results

### Task 4.4: Document Results
- [ ] Record test results in `docs/checklist.md`
- [ ] Screenshot or log output as evidence

---

## Phase 5: Lock Down (workspace: `terraform/04_network_policy`)

### Task 5.1: Snowflake Network Policy
- [ ] Create `snowflake_network_policy` resource
- [ ] Create network rules:
  - Rule 1: VPC CIDR (10.0.0.0/16) — PrivateLink traffic
  - Rule 2: Operator IP (var.operator_ip) — debug/admin access
- [ ] Allowed list: both network rules
- [ ] Blocked list: all other access (implicit)
- [ ] NOTE: Only activate AFTER confirming PrivateLink works. Locking down
      prematurely will lock you out of Snowflake.

### Task 5.2: Activate Network Policy
- [ ] Attach to account level
- [ ] Verify you can still connect via PrivateLink after activation (from EC2)
- [ ] Verify Snowsight works from your laptop (operator IP allowed)
- [ ] Document rollback procedure (how to remove policy if locked out)

### Task 5.3: Demonstrate Enforcement
- [ ] Temporarily remove operator IP from allowed list
- [ ] Verify laptop is blocked from Snowsight
- [ ] Re-add operator IP
- [ ] Document the before/after for article

---

## Phase 6: Cleanup and Documentation

### Task 6.1: Stop/Destroy Test Resources
- [ ] Stop EC2 instance after initial validation (keeps it available for re-testing)
- [ ] Destroy (`terraform destroy` in `terraform/03_ec2_test`) when PrivateLink is
      confirmed stable and no further testing is needed
- [ ] Verify EC2 instance terminated, key pair deleted, security group removed

### Task 6.2: Documentation
- [ ] Write `README.md` with project overview + quick start
- [ ] Write `docs/architecture.md` with diagram
- [ ] Write `docs/runbook.md` with step-by-step instructions
- [ ] Write `docs/checklist.md` adapted from book Table 2-2
- [ ] Write `docs/troubleshooting.md` with common issues

### Task 6.3: CI/CD Pipeline
- [ ] Create `.github/workflows/terraform.yml`
- [ ] Plan on PR, apply on merge to main
- [ ] Workspace dependency order: networking → privatelink → network_policy
- [ ] Exclude `03_ec2_test` from CI/CD (manual/ephemeral only)

### Task 6.4: Final Commits
- [ ] Commit and push `aws-org-infra` changes (IAM role, OIDC trust)
- [ ] Commit and push `snowflake_aws_privatelink` initial implementation
- [ ] Create PR in both repos for review

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | IAM role, not user | Avoid long-lived credentials; follows existing org pattern |
| D2 | Sandbox mode | Cost-effective experimentation; promote to production later |
| D3 | 3 AZs for endpoints | High availability per Well-Architected |
| D4 | NAT in 1 AZ only | Cost optimization for sandbox; production would use all AZs |
| D5 | EC2 test as separate workspace | Can be stopped/destroyed independently without affecting infra |
| D6 | Network policy as last step | Prevents accidental lockout during setup |
| D7 | S3 gateway endpoint included | Required for internal stage traffic to stay on backbone |
| D8 | private_dns_enabled = false | Manual DNS via Route53 gives more control + supports OCSP |
| D9 | Book as guide, current docs for implementation | Book is 2023; Snowflake self-service and provider have evolved |
| D10 | Terraform >= 1.10, < 2.0 | Matches org standard; avoids breaking changes from TF 2.x |
