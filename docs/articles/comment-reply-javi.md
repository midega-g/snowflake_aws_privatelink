# Reply to Javi — operator_ip rotation under an active network policy

## Full version

Thanks Javi, glad the `private_dns_enabled = false` piece landed, that's the part that trips almost everyone up because the AWS docs make `true` sound like the default you always want.

On your PCI-DSS evaluation: you've already spotted the trap. The $59/month floor and the Business Critical dependency are exactly the two numbers people skip when they reach for PrivateLink reflexively. For cardholder data you likely do land on PrivateLink, but quantifying it first means you can defend the choice to an auditor instead of just asserting it.

On the operator_ip rotation, my answer is firmly: through the pipeline, not Snowsight. Here's the reasoning.

Doing an `ALTER NETWORK POLICY SET ALLOWED_IP_LIST` by hand in a Snowsight session works, and it's tempting precisely because that session is already inside PrivateLink so you're not at risk of locking yourself out mid-edit. But it breaks exactly what you're worried about: the allowlist in Snowflake drifts from the allowlist in your Terraform state. The next `terraform plan` shows a diff, someone "fixes" it by reverting your manual change, and now the ops team is locked out again. The manual edit also leaves a thin audit trail: you get the Snowflake query history entry, but no diff, no reviewer, no reason-for-change.

So in practice I keep the IP list as the versioned source of truth and change it the same way it was created:

- `operator_ip` is a Terraform variable, and the change is a PR against that variable. The PR is the audit record: who, what, when, approved by whom.
- The apply runs through CI assuming a scoped role, not from someone's laptop. Snowflake's query history then shows the change coming from the automation identity, which you can tie back to the merged commit.
- The VPC CIDR stays hardcoded on the allowlist and never rotates, so even if an operator IP change goes wrong, the recovery path (connect from inside the VPC, unset the policy) is always open. That's the safety net that makes automating the rest comfortable.

One caveat worth flagging for your travel-company context: operator IPs that change often (home offices, VPN exit IPs that shift) are a sign the IP allowlist is the wrong tool for human access. For your situation I'd consider keeping the network policy strictly for the PrivateLink CIDR and the automation path, and handling human/ops access through SSO plus a Snowsight session that already enters via PrivateLink, rather than chasing their public IPs on the allowlist at all. You rotate IPs far less often when the only IPs on the list are infrastructure, not people.

The SSM-document angle you mentioned is a reasonable middle ground if you're not fully on Terraform-via-CI yet, as long as the document is versioned and the execution is logged. The principle is the same either way: the change should be reviewable and replayable, and Snowflake should never be the system of record for something your IaC also manages.

---

## Shortened version

Thanks Javi, glad the `private_dns_enabled = false` piece landed, that's the part that trips almost everyone up.

Good instinct on the PCI-DSS side: the $59/month floor and the Business Critical dependency are the two numbers people skip when they reach for PrivateLink reflexively. You'll likely still land on it for cardholder data, but quantifying it first means you can defend the choice to an auditor instead of just asserting it.

On rotating `operator_ip`: through the pipeline, not Snowsight. Editing the allowlist by hand in a Snowsight session works and won't lock you out mid-edit, but it drifts from your Terraform state. The next `terraform plan` shows a diff, someone reverts it, and the ops team is locked out again. You also get a thin audit trail: a query-history entry, but no diff, no reviewer, no reason-for-change.

So I keep the IP list as the versioned source of truth: `operator_ip` is a Terraform variable, and a change is a PR against it (that PR is the audit record), applied through automation under a scoped role rather than someone's laptop. The VPC CIDR stays hardcoded on the allowlist and never rotates, so the recovery path (connect from inside the VPC, unset the policy) is always open.

One caveat for your context: operator IPs that change often (home offices, shifting VPN exit IPs) are a sign the IP allowlist is the wrong tool for human access. I'd keep the policy strictly for the PrivateLink CIDR and the automation path, and handle human access through SSO over a Snowsight session that already enters via PrivateLink, rather than chasing people's public IPs at all. The SSM-document route is a fine middle ground if you're not on Terraform-via-CI yet, as long as it's versioned and logged. Either way: the change should be reviewable and replayable, and Snowflake should never be the system of record for something your IaC manages.
