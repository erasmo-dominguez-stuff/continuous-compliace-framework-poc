# Example CUSTOM organizational policy for the CCF GitHub repositories plugin.
#
# It asserts an internal baseline against the repository metadata the plugin
# collects (exposed as `input`). Bundle it with `make policy-build` and push it
# with `make policy-push`, then reference the resulting OCI bundle under
# ccf-agent.config.plugins.<plugin>.policies (see values/plugins/custom-policies.yaml).
#
# Run `make policy-test` to validate the logic before shipping.
package compliance_framework.custom_repo_baseline

# Structured risk/remediation metadata surfaced in CCF reports (OSCAL-style).
risk_templates := [
	{
		"name": "Repository violates the internal baseline",
		"title": "Repository Drifts From the Organizational Baseline",
		"statement": "Repositories that are archived without notice, lack a description, or are unexpectedly public increase operational and supply-chain risk: ownership becomes unclear, consumers cannot understand intent, and code may be exposed beyond its intended audience.",
		"likelihood_hint": "moderate",
		"impact_hint": "moderate",
		"remediation": {
			"title": "Bring the repository back in line with the baseline",
			"description": "Add a description, confirm the intended visibility, and unarchive or formally retire the repository.",
			"tasks": [
				{"title": "Add a meaningful repository description"},
				{"title": "Confirm the repository visibility matches policy (private unless approved)"},
				{"title": "Unarchive the repository or record an approved exception"},
			],
		},
	},
]

# Archived repositories drift out of compliance silently.
violation contains {"id": "repo_archived"} if {
	input.settings.archived == true
}

# Every repository must carry a non-empty description.
violation contains {"id": "missing_description"} if {
	not has_description
}

has_description if {
	input.settings.description
	input.settings.description != ""
}

# Public repositories are only allowed when explicitly approved via policy_data
# (ccf-agent.config.plugins.<plugin>.policy_data.allow_public_repositories: true).
violation contains {"id": "unexpected_public_visibility"} if {
	input.settings.visibility == "public"
	not allow_public_repositories
}

default allow_public_repositories := false

allow_public_repositories if {
	data.custom.allow_public_repositories == true
}

title := "Repository meets the internal baseline"

description := "Repositories must be active, documented, and private unless explicitly approved."

remarks := "This baseline keeps repositories discoverable and accountable: a description communicates intent, controlled visibility prevents accidental exposure, and avoiding silent archival keeps ownership clear. Approved public repositories can be allow-listed through the plugin's policy_data."
