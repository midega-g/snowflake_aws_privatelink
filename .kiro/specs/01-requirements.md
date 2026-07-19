# Requirements — Snowflake AWS PrivateLink

## 1. Project Goal

Establish private connectivity between an AWS VPC (in the shared sandbox account)
and a Snowflake Business Critical account in us-west-2 using AWS PrivateLink, ensuring
all traffic between the VPC and Snowflake traverses the AWS backbone (never the
public internet).

## 2. Functional Requirements

### FR-01: PrivateLink Authorization (Snowflake-side)

- Enable PrivateLink on the Snowflake account using `SYSTEM$AUTHORIZE_PRIVATELINK`
- Verify authorization with `SYSTEM$GET_PRIVATELINK`
- Retrieve endpoint configuration with `SYSTEM$GET_PRIVATELINK_CONFIG`
- Provide a helper script for the one-time authorization (federation token generation + SQL execution)
- Provide a revocation script for cleanup

### FR-02: VPC Provisioning

- Create a VPC in us-west-2 within the sandbox account
- 3 Availability Zones (public + private subnets in each)
- CIDR block: 10.0.0.0/16 (or configurable via variable)
- DNS hostnames and DNS support enabled
- NAT Gateway in 1 AZ (for outbound internet from private subnets)
- Internet Gateway (for public subnets — EC2 testing)

### FR-03: VPC Interface Endpoint (Snowflake PrivateLink)

- Create `aws_vpc_endpoint` of type "Interface" using the `privatelink-vpce-id`
  from `snowflake_system_get_privatelink_config` data source
- Place endpoint interfaces in private subnets across all 3 AZs
- Security group allowing inbound port 443 (HTTPS) and port 80 (OCSP) from VPC CIDR
- `private_dns_enabled = false` (DNS handled via Route53 private hosted zone)

### FR-04: S3 Gateway Endpoint (Internal Stage Traffic)

- Create `aws_vpc_endpoint` of type "Gateway" for `com.amazonaws.us-west-2.s3`
- Associate with route tables for private subnets
- This ensures Snowflake internal stage traffic (SELECT results, COPY INTO, etc.)
  stays on the AWS backbone

### FR-05: DNS Configuration (Route53)

- **Hosted Zone 1:** Private hosted zone for `privatelink.snowflakecomputing.com`
  - CNAME record: `<account_identifier>.us-west-2.privatelink.snowflakecomputing.com`
    → VPC Endpoint regional DNS name
  - CNAME record: OCSP URL → VPC Endpoint regional DNS name
  - CNAME record: Snowsight regionless URL → VPC Endpoint regional DNS name
  - CNAME record: Snowsight regional URL → VPC Endpoint regional DNS name
  - Associate zone with the VPC

- **Hosted Zone 2:** Private hosted zone for Snowflake internal S3 bucket stage URL
  - A record pointing to S3 gateway endpoint IPs
  - Associate zone with the VPC

### FR-06: EC2 Test Instances (Connectivity Validation)

- **Linux instance** (Amazon Linux 2023) in a public subnet:
  - Key pair for SSH access
  - Security group allowing SSH (port 22) from operator IP only
  - SnowSQL pre-installed via user_data
  - Used for: nslookup, telnet, SnowSQL connectivity tests

- **Windows instance** (Windows Server 2022) in a public subnet:
  - Key pair for RDP password decryption
  - Security group allowing RDP (port 3389) from operator IP only
  - Used for: browser-based Snowsight access via PrivateLink (visual proof)
- Used to run: `nslookup`, `telnet` (port 443/80), and SnowSQL connection test
- Stop after initial validation; destroy when PrivateLink is confirmed stable
- Terraform workspace can be destroyed independently without affecting PrivateLink

### FR-07: Network Policy (Block Public Access — Post-Validation)

- After PrivateLink is validated, create a Snowflake network policy restricting
  access to:
  - VPC CIDR (10.0.0.0/16) — PrivateLink traffic from within VPC
  - Operator IP (configurable) — debug/admin access from laptop
- All other public internet access to the Snowflake account is blocked
- Implemented via `snowflake_network_policy` + `snowflake_network_rule` resources
- Demonstrate enforcement: remove operator IP → verify laptop blocked → re-add

### FR-08: IAM Role in Management Account

- Create `snowflake-privatelink-admin` IAM role in the management account
- Scoped permissions: STS federation token, EC2 (VPC endpoints, security groups),
  Route53, and sandbox account assume-role
- Assumable by the existing admin user
- Lives in `aws-org-infra` under `01_org_setup/03_security/01_management_iam/`
  as a separate `.tf` file

## 3. Non-Functional Requirements

### NFR-01: Tagging

ALL resources must carry these tags:

| Tag Key | Value |
|---------|-------|
| `project:name` | snowflake-privatelink |
| `project:environment` | sandbox |
| `project:owner` | cloudops-team |
| `project:managed-by` | terraform |
| `project:repo` | snowflake_aws_privatelink |
| `project:cost-center` | data-platform |

Resource-specific `Name` tags are also required on all resources that support them.

### NFR-02: Well-Architected Framework Compliance

- **Security:** Least-privilege IAM, security groups scoped to VPC CIDR only,
  private subnets for endpoints, network policy blocking public access
- **Reliability:** Endpoints in all 3 AZs for high availability
- **Cost Optimization:** NAT in 1 AZ only (sandbox), EC2 instance stopped after
  testing and destroyed when no longer needed, no idle resources left running
- **Operational Excellence:** All infrastructure as code, helper scripts documented,
  checklist for manual steps
- **Performance:** Interface endpoints in all AZs minimize cross-AZ latency

### NFR-03: State Management

- State stored in the existing S3 bucket: `ecommerce-tf-state-mgmt`
- State key prefix: `projects/snowflake-privatelink/`
- Each workspace gets its own key (e.g., `projects/snowflake-privatelink/networking/terraform.tfstate`)
- S3-native locking (`use_lockfile = true`)

### NFR-04: Version Constraints

| Tool | Constraint |
|------|-----------|
| Terraform CLI | `>= 1.10.0, < 2.0.0` |
| AWS Provider | `~> 6.38` |
| Snowflake Provider | `>= 1.0` (latest stable, with preview features enabled) |

### NFR-05: Documentation

- README with architecture diagram
- Runbook for the one-time Snowflake authorization
- Checklist (adapted from the book's Table 2-2) with IaC equivalents noted
- Troubleshooting guide

### NFR-06: CI/CD

- GitHub Actions pipeline triggered on PR (plan) and merge to main (apply)
- Uses OIDC authentication (trust policy added to `aws-org-infra`)
- Workspace dependency order enforced

## 4. Constraints

- PrivateLink requires Snowflake Business Critical edition (confirmed available)
- AWS region and Snowflake region MUST match (both us-west-2)
- Cross-region PrivateLink is possible via custom endpoint service but out of scope
- SSO over PrivateLink is exclusive — cannot have both public and PrivateLink SSO
  simultaneously (out of scope for initial implementation)
- Federation token expires in 12 hours — only needed for one-time authorization
- The `snowflake_system_get_privatelink_config` data source is a preview feature
  requiring explicit opt-in in provider config

## 5. Assumptions

- The sandbox account (`06_sandbox`) is already provisioned and applied in `aws-org-infra`
- The management account admin user has credentials configured locally
- A Snowflake Business Critical account exists in us-west-2 with ACCOUNTADMIN access
- The GitHub repo `snowflake_aws_privatelink` will be created as part of this project
- The existing S3 state bucket is accessible from us-west-2 (bucket is in af-south-1
  but S3 backends work cross-region)

## 6. Out of Scope

- AWS Direct Connect
- Cross-region PrivateLink
- SSO configuration over PrivateLink
- Multi-account PrivateLink (connecting multiple AWS accounts to one Snowflake account)
- Automated security monitoring of authorized endpoints (noted as future enhancement)
- S3 Interface Endpoint for internal stages (recommended by Snowflake for Iceberg/managed
  storage — current S3 Gateway Endpoint covers standard use cases; interface endpoint is
  a future upgrade if Iceberg tables are adopted)
- VPN/Direct Connect for laptop access (operator uses allowed IP in network policy instead)
