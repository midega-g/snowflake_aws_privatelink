# Snowflake AWS PrivateLink — Phase 0: Introduction & Common Patterns

## The Problem

In healthcare, a query returning patient records traverses the public internet before reaching your application. In finance, trade execution data crosses network boundaries visible to anyone monitoring traffic patterns. In government, classified workloads sharing a network path with consumer traffic violates compliance mandates before a single byte is processed.

These sectors don't just need encryption — they need *network isolation*. The data can't share a path with public traffic, period.

### How Snowflake Normally Works

When you create a Snowflake account, Snowflake provisions everything — compute, storage, metadata — inside *their* AWS account, in *their* VPC. You never see this infrastructure. You don't manage it. It's a fully managed service.

Your applications, ETL pipelines, and BI tools live in *your* AWS account, in *your* VPC. When they connect to Snowflake, they resolve a public DNS name (`xyz.snowflakecomputing.com`) to a public IP address, and traffic flows over the public internet:

```
Your VPC → Internet Gateway → Public Internet → Snowflake's VPC
```

The connection is encrypted (TLS), so the *content* is protected. But the *traffic path* is public. Network monitoring tools can see that you're communicating with Snowflake, how often, and how much data flows. For many workloads, this is perfectly acceptable.

For regulated industries, it's not.

### What PrivateLink Changes

AWS PrivateLink creates a private network path between your VPC and Snowflake's VPC. Traffic never leaves the AWS backbone:

```
Your VPC → VPC Endpoint (private IP) → AWS Backbone → Snowflake's VPC
```

No internet gateway involved. No public IP addresses. No exposure to external network monitoring. The connection is invisible outside of AWS's internal network.

This is what compliance frameworks like HIPAA, PCI-DSS, SOC 2, and FedRAMP mean when they require "private connectivity" or "network segmentation" for data in transit.

---

## Do You Actually Need This?

PrivateLink isn't the only way to secure Snowflake connectivity. Before committing to the infrastructure and cost, check which requirement you're actually solving:

| Your Requirement | Solution | Cost | PrivateLink Needed? |
|-----------------|----------|------|-------------------|
| "Encrypt data in transit" | Standard TLS (already on by default) | $0 | No |
| "Restrict who can connect" | Snowflake network policy (IP allowlist) | $0 | No |
| "Traffic must not traverse the public internet" | AWS PrivateLink | ~$59/month AWS + Business Critical edition | **Yes** |
| "Private from on-prem to Snowflake" | Direct Connect + PrivateLink | $200-2000+/month | Yes (plus physical cross-connect) |

**If your compliance team says "encrypted in transit"** — you already have it. Snowflake forces TLS on every connection. No action needed.

**If they say "restrict access to known IPs"** — a network policy (free, Snowflake-side configuration) handles this without any AWS infrastructure.

**If they say "private network path" or "no public internet traversal"** — that's PrivateLink. There's no cheaper alternative for true network isolation between two separate AWS accounts.

**The hidden cost:** PrivateLink requires Snowflake **Business Critical** edition. The edition upgrade (Snowflake's pricing, separate from AWS costs) is likely more expensive than the $59/month in AWS infrastructure. If you're on Standard or Enterprise edition, the edition change is part of the decision.

This series assumes you've already decided PrivateLink is required — either for compliance, security posture, or because you're on Business Critical and want the tightest possible access controls.

---

## What We're Building

By the end of this series, you'll have:

- A VPC with private subnets connected to Snowflake via PrivateLink
- DNS resolution that routes Snowflake URLs to private IPs inside your VPC
- S3 internal stage traffic staying on the AWS backbone
- Browser access to Snowsight via PrivateLink (from inside the VPC)
- A network policy blocking all public access — only PrivateLink and your admin IP allowed

---

## What You Can't Achieve with This Setup

Before investing time, know the boundaries:

| Limitation | Explanation |
|-----------|-------------|
| Cross-region PrivateLink | Your VPC and Snowflake account must be in the same AWS region. We use us-west-2 for both. |
| SSO + PrivateLink simultaneously | You can't have both public SSO and PrivateLink SSO active at the same time on one account. |
| Laptop access via PrivateLink (without VPN) | PrivateLink only works from inside the VPC. Your laptop connects over the public internet (allowed via network policy). |
| Free | The VPC Interface Endpoint costs ~$22/month. NAT Gateway adds ~$37/month. Minimum viable setup is ~$59/month. |

---

## Prerequisites

You'll need these before starting Phase 1:

| Requirement | Details |
|-------------|---------|
| Snowflake Business Critical account | PrivateLink is not available on Standard or Enterprise editions |
| AWS account in the same region as Snowflake | Both must be in us-west-2 (or whichever region your Snowflake account uses) |
| Terraform >= 1.10.0 | Infrastructure as code — all resources are managed via Terraform |
| AWS CLI configured | With credentials that can create VPCs, endpoints, Route53 zones |
| Snowflake ACCOUNTADMIN access | Required for PrivateLink authorization and network policy |
| `~/.snowflake/config` | Snowflake credentials for the Terraform provider |

> **Note on AWS account setup:** This series uses an AWS Organizations multi-account structure (management account + sandbox account) with cross-account role assumption. If you're using a standalone AWS account, the setup is simpler — skip the `assume_role` blocks in the provider configuration and remove the `data.terraform_remote_state.sandbox` references. A single IAM user with AdministratorAccess in a standalone account will work without permission issues.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ AWS (us-west-2)                                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ VPC 10.0.0.0/16                                     │    │
│  │                                                     │    │
│  │  ┌──────────────┐       ┌───────────────────────┐   │    │
│  │  │ Public       │       │ Private               │   │    │
│  │  │ Subnets      │       │ Subnets               │   │    │
│  │  │              │       │                       │   │    │
│  │  │ • EC2 Test   │       │ • VPC Endpoint ───────┼───┼──────► Snowflake
│  │  │ • NAT GW     │       │   (Interface, 3 AZs)  │   │    │   (PrivateLink)
│  │  │ • IGW        │       │ • S3 Gateway Endpoint │   │    │
│  │  │              │       │ • Route53 Private Zone│   │    │
│  │  └──────────────┘       └───────────────────────┘   │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

The VPC Endpoint creates Elastic Network Interfaces (ENIs) in your private subnets — one per Availability Zone. When anything inside your VPC resolves a Snowflake URL, Route53's private hosted zone returns these ENI private IPs instead of Snowflake's public IPs. Traffic flows to the ENI, through PrivateLink, directly to Snowflake's VPC. Never leaves AWS.



Top level: A large container labeled "AWS Cloud (us-west-2)" holding everything on the AWS side.

Inside AWS Cloud, two account containers:

1. Management Account (top-left, pink border) — contains a single icon representing the IAM role (OrgSnowflakePrivateLinkAdmin) used to assume into the
sandbox account.

2. Sandbox Account (below, pink border, larger) — where all PrivateLink infrastructure lives. Contains the VPC.

Inside the VPC (10.0.0.0/16):

- **Public Subnets** (left side, green background) — three AZs (us-west-2a/b/c):
  - Linux EC2 instance (labeled "SSH + SnowSQL") — for CLI-based connectivity testing
  - Windows EC2 instance (labeled "RDP + Snowsight") — for browser-based testing
  - NAT Gateway — outbound internet for private subnets
  - Internet Gateway — outbound internet for public subnets

- **Private Subnets** (right side, blue background) — three AZs:
  - VPC Endpoint (Interface) — the PrivateLink connection point to Snowflake, with ENIs in all 3 AZs
  - S3 Gateway Endpoint — keeps internal stage traffic on the AWS backbone
  - Route53 Private Zone — resolves Snowflake URLs to the VPCE private IPs (6 CNAME records)
  - Security Group annotation — ports 443 + 80 allowed from VPC CIDR only

Outside AWS (right side): A Snowflake box representing the Business Critical account (us-west-2), annotated with "Network Policy: VPC CIDR + Operator 
IPs."

Connections:
- Dashed line from Management Account → Sandbox Account (labeled "AssumeRole")
- Dashed line from Linux EC2 → VPC Endpoint (labeled "SnowSQL")
- Dashed line from Windows EC2 → VPC Endpoint (labeled "Snowsight")
- Dashed line from Route53 → VPC Endpoint (labeled "DNS")
- **Thick blue line** from VPC Endpoint → Snowflake (labeled "AWS PrivateLink — private, no internet") — this is the main connection, visually 
emphasized

Key visual message: Everything converges on the VPC Endpoint in the private subnets. The test instances, DNS, and security group all feed into it, and
the single thick blue line to Snowflake shows that all traffic takes one private path — no public internet involved.

### Why 3 Availability Zones? Where Does Each Resource Actually Live?

The VPC has 3 public and 3 private subnets (one per AZ), but not everything uses all three. Here's the actual placement:

| Resource | Deployed to | Why |
|----------|-------------|-----|
| VPC Endpoint (Interface) ENIs | All 3 AZs (private subnets) | **High availability** — if one AZ fails, PrivateLink routes through the remaining two |
| EC2 test instances | 1 AZ only (us-west-2a, public subnet) | Ephemeral test tools — HA not needed |
| NAT Gateway | 1 AZ only (us-west-2a, public subnet) | Cost optimization for sandbox (~$37/month per NAT) |
| Internet Gateway | VPC-wide (not AZ-specific) | One per VPC, serves all subnets |
| S3 Gateway Endpoint | VPC-wide (route table association) | Route-based, not subnet-specific |

**The VPC Endpoint is the reason we need 3 AZs.** PrivateLink creates an ENI in each specified subnet. If us-west-2a goes down, DNS automatically routes to the ENI in us-west-2b or 2c. This is the core reliability requirement for private connectivity.

**Everything else is single-AZ for cost.** In production, you'd have 3 NAT Gateways (~$110/month) and application instances spread across all AZs. In a sandbox, single-AZ for non-critical resources saves money without affecting PrivateLink availability.

**Subnets are free.** Creating 3 public + 3 private subnets costs nothing. The cost comes from what you deploy *into* them. Having the subnets ready means you can scale to multi-AZ production without re-architecting the network.


---

## How the Series is Structured

| Phase | What it builds | Depends on |
|-------|---------------|-----------|
| **1: VPC Networking** | VPC, subnets, IGW, NAT, route tables | Nothing |
| **2: PrivateLink & DNS** | Authorization, VPC Endpoint, security groups, Route53 CNAMEs | Phase 1 |
| **3: Validating Connectivity** | EC2 instances (Linux SSH + Windows RDP), DNS/port/SnowSQL/Snowsight tests | Phase 2 |
| **4: Locking Down Public Access** | Snowflake network policy, enforcement demonstration | Phase 3 validated |

Each phase has its own Terraform workspace with isolated state. You can destroy test resources (Phase 3) without affecting the PrivateLink infrastructure (Phase 2).

---

## Common Terraform Patterns

All workspaces in this project share the same patterns. This section covers them once — subsequent articles reference back here.

### Provider Configuration (AWS)

Every workspace assumes a role into the target account. If your credentials are in an opt-in region (af-south-1, me-south-1, ap-east-1, etc.) and your resources are in a different region, you need the STS global endpoint workaround:

```hcl
provider "aws" {
  region = "us-west-2"

  assume_role {
    role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/OrganizationAccountAccessRole"
  }

  # STS workaround: af-south-1 is an opt-in region whose regional STS
  # endpoint rejects cross-region AssumeRole. Routing through the global
  # endpoint (sts.amazonaws.com) resolves this. The global endpoint
  # requires sts_region = "us-east-1" for request signing.
  sts_region = "us-east-1"

  endpoints {
    sts = "https://sts.amazonaws.com"
  }

  default_tags {
    tags = {
      "project:name"        = "snowflake-privatelink"
      "project:environment" = "sandbox"
      "project:managed-by"  = "terraform"
    }
  }
}
```

**Why `sts_region = "us-east-1"`?** The global STS endpoint (`sts.amazonaws.com`) requires requests to be signed with `us-east-1` as the region parameter. This is not a universal rule — it only applies when you're routing through the global endpoint. You only *need* the global endpoint because opt-in regions (like af-south-1) have regional STS endpoints that reject cross-region AssumeRole.

**When does this apply?** Only if your credentials originate from an opt-in region and you're targeting a different region. If your credentials and resources are both in standard regions (e.g., us-east-1, us-west-2), you don't need the `sts_region` or `endpoints` blocks at all.

If you're using a standalone account (no Organizations), your provider is simpler:

```hcl
provider "aws" {
  region = "us-west-2"
  # No assume_role, no STS workaround needed
}
```

### Provider Configuration (Snowflake)

Reads credentials from `~/.snowflake/config`:

```hcl
provider "snowflake" {
  profile                  = "default"
  role                     = "ACCOUNTADMIN"
  preview_features_enabled = ["snowflake_system_get_privatelink_config_datasource"]
}
```

The config file (not committed to git):

```toml
[default]
organization_name = "<your-org>"
account_name = "<your-account>"
user = "<your-user>"
authenticator = "snowflake"
password = "<your-password>"
role = "ACCOUNTADMIN"
```

### Remote State Pattern

Each workspace reads upstream outputs via `terraform_remote_state`:

```hcl
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "your-state-bucket"
    key    = "projects/snowflake-privatelink/networking/terraform.tfstate"
    region = "af-south-1"  # Where the state bucket lives (not where resources are)
  }
}

# Then reference outputs:
local.vpc_id = data.terraform_remote_state.networking.outputs.vpc_id
```

### Backend Configuration

All workspaces use S3 with native locking:

```hcl
terraform {
  backend "s3" {
    bucket       = "your-state-bucket"
    key          = "projects/snowflake-privatelink/<workspace>/terraform.tfstate"
    region       = "af-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

### Tagging Strategy

All AWS resources get project tags via `default_tags` (set once in the provider, applied to everything). Resource-specific `Name` tags are added per resource:

```hcl
tags = {
  Name = "snowflake-privatelink-<resource>"
}
```

---

## Cost Summary

Before you start — here's what you'll pay at each stage:

| After Phase | Monthly Cost | Main Driver |
|-------------|-------------|-------------|
| Phase 1 | ~$37/month | NAT Gateway ($32.85) + EIP ($3.65) |
| Phase 2 | ~$59/month | + VPC Interface Endpoint ($21.90) + Route53 ($0.50) |
| Phase 3 | ~$98/month | + EC2 test instances (temporary) |
| Phase 4 | ~$59/month | Same as Phase 2 (test instances destroyed, policy is free) |

**Steady state after testing:** ~$59/month. The NAT Gateway can be destroyed when not needed (saves $37/month) — PrivateLink doesn't use it.

---

## Repository Structure

```
snowflake_aws_privatelink/
├── terraform/
│   ├── 01_networking/       # VPC, subnets, IGW, NAT, route tables
│   ├── 02_privatelink/      # Auth user, VPCE, S3 gateway, SG, Route53 DNS
│   ├── 03_ec2_test/         # Ephemeral test instances (destroy after use)
│   └── 04_network_policy/   # Snowflake network policy (Snowflake-side only)
├── scripts/
│   ├── authorize-privatelink.sh   # One-time Snowflake authorization
│   ├── verify-privatelink.sh      # Check authorization status
│   ├── revoke-privatelink.sh      # Revoke (cleanup)
│   └── test-connectivity.sh       # DNS + port tests (run from EC2)
└── docs/
    ├── architecture.md
    ├── runbook.md
    └── troubleshooting.md
```

---

## What's Next

In **Phase 1**, we'll create the VPC networking foundation — the subnets, gateways, and route tables that the PrivateLink endpoint will live in. No Snowflake configuration yet; just the AWS networking layer.

If you're following along, make sure your AWS CLI is authenticated and you can create resources in your target region. Run `aws sts get-caller-identity` to confirm.

---

*Full source code: [github.com/midega-g/snowflake_aws_privatelink](https://github.com/midega-g/snowflake_aws_privatelink)*
