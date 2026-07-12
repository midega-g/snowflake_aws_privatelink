# Checklist — Snowflake AWS PrivateLink

Adapted from the book's Table 2-2. Items marked with 🤖 are managed by Terraform
(no manual tracking needed). Items marked with 🖐️ require manual action or recording.

## Pre-requisites

| # | Item | Value | Status |
|---|------|-------|--------|
| 1 | 🖐️ Snowflake account identifier | _fill in_ | ☐ |
| 2 | 🖐️ Snowflake organization name | _fill in_ | ☐ |
| 3 | 🤖 AWS Sandbox Account ID | `terraform output` from `06_sandbox` | ☐ |
| 4 | 🤖 AWS Region | us-east-1 | ☐ |
| 5 | 🖐️ Snowflake Region | us-east-1 (AWS_US_EAST_1) | ☐ |
| 6 | 🖐️ Snowflake edition confirmed Business Critical | Yes/No | ☐ |
| 7 | 🤖 IAM Role ARN (`snowflake-privatelink-admin`) | `terraform output` | ☐ |

## Phase 0: Authorization (One-time)

| # | Item | Value | Status |
|---|------|-------|--------|
| 8 | 🖐️ Federation token generated | `aws sts get-federation-token --name snowflake` | ☐ |
| 9 | 🖐️ `SYSTEM$AUTHORIZE_PRIVATELINK` executed | Success / "Account is authorized" | ☐ |
| 10 | 🖐️ `SYSTEM$GET_PRIVATELINK` verification | "Account is authorized for PrivateLink" | ☐ |

## Phase 1: Networking

| # | Item | Value | Status |
|---|------|-------|--------|
| 11 | 🤖 VPC ID | `terraform output vpc_id` | ☐ |
| 12 | 🤖 VPC CIDR | 10.0.0.0/16 | ☐ |
| 13 | 🤖 Public subnet IDs (3x) | `terraform output public_subnet_ids` | ☐ |
| 14 | 🤖 Private subnet IDs (3x) | `terraform output private_subnet_ids` | ☐ |
| 15 | 🤖 Internet Gateway ID | `terraform output igw_id` | ☐ |
| 16 | 🤖 NAT Gateway ID | `terraform output nat_gateway_id` | ☐ |

## Phase 2: PrivateLink

| # | Item | Value | Status |
|---|------|-------|--------|
| 17 | 🤖 `privatelink-vpce-id` (Snowflake service name) | From Snowflake data source | ☐ |
| 18 | 🤖 `privatelink-account-url` | From Snowflake data source | ☐ |
| 19 | 🤖 `privatelink-ocsp-url` | From Snowflake data source | ☐ |
| 20 | 🤖 Security Group ID (VPCE) | `terraform output sg_id` | ☐ |
| 21 | 🤖 VPC Endpoint ID (Snowflake) | `terraform output vpce_id` | ☐ |
| 22 | 🤖 VPC Endpoint DNS Name | `terraform output vpce_dns_name` | ☐ |
| 23 | 🤖 S3 Gateway Endpoint ID | `terraform output s3_endpoint_id` | ☐ |
| 24 | 🤖 Route53 Hosted Zone ID | `terraform output hosted_zone_id` | ☐ |
| 25 | 🤖 CNAME record (account URL) | `terraform output` | ☐ |
| 26 | 🤖 CNAME record (OCSP) | `terraform output` | ☐ |

## Phase 3: EC2 Testing

| # | Item | Value | Status |
|---|------|-------|--------|
| 27 | 🤖 EC2 Instance ID | `terraform output instance_id` | ☐ |
| 28 | 🤖 EC2 Public IP | `terraform output public_ip` | ☐ |
| 29 | 🤖 Key Pair Name | `terraform output key_pair_name` | ☐ |
| 30 | 🖐️ SSH command | `ssh -i <key> ec2-user@<ip>` | ☐ |

## Phase 4: Validation

| # | Item | Value | Status |
|---|------|-------|--------|
| 31 | 🖐️ nslookup resolves to private IPs | Yes/No + IPs recorded | ☐ |
| 32 | 🖐️ IPs match VPCE ENI addresses | Yes/No | ☐ |
| 33 | 🖐️ telnet port 443 connects (all 3 AZs) | Connected / Failed | ☐ |
| 34 | 🖐️ telnet port 80 connects (all 3 AZs) | Connected / Failed | ☐ |
| 35 | 🖐️ SnowSQL connection via PrivateLink URL | Connected / Failed | ☐ |

## Phase 5: Lock Down

| # | Item | Value | Status |
|---|------|-------|--------|
| 36 | 🤖 Network policy name | `terraform output` | ☐ |
| 37 | 🖐️ Verified access still works after policy | Yes/No | ☐ |
| 38 | 🖐️ Verified public access is blocked | Yes/No | ☐ |

## Phase 6: Cleanup

| # | Item | Value | Status |
|---|------|-------|--------|
| 39 | 🖐️ EC2 instance stopped after testing | `aws ec2 stop-instances` or console | ☐ |
| 40 | 🖐️ EC2 instance destroyed when stable | `terraform destroy` in 03_ec2_test | ☐ |
| 41 | 🖐️ Key pair file securely deleted | Yes/No | ☐ |
| 42 | 🖐️ All documentation written | Yes/No | ☐ |
| 43 | 🖐️ CI/CD pipeline tested | Yes/No | ☐ |

---

## Rollback Procedures

### If locked out by network policy:
1. Use Snowflake Support to temporarily disable the network policy
2. Or: connect from within the allowed CIDR and `ALTER ACCOUNT UNSET NETWORK_POLICY`

### If PrivateLink authorization fails:
1. Regenerate federation token (old one may have expired)
2. Ensure AWS region matches Snowflake region
3. Confirm Business Critical edition

### If VPC endpoint shows "Failed":
1. Verify Snowflake authorization was successful first
2. Check service name matches region
3. Check security group allows 443/80 inbound
