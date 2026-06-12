package compliance_framework.custom_repo_baseline_test

import data.compliance_framework.custom_repo_baseline as policy

# A repository that satisfies the full baseline produces no violations.
test_compliant_repo_ok if {
	inp := {"settings": {
		"archived": false,
		"description": "Service that does a thing",
		"visibility": "private",
	}}

	count(policy.violation) == 0 with input as inp
}

test_archived_repo_violation if {
	inp := {"settings": {
		"archived": true,
		"description": "Service that does a thing",
		"visibility": "private",
	}}

	policy.violation == {{"id": "repo_archived"}} with input as inp
}

test_missing_description_violation if {
	inp := {"settings": {
		"archived": false,
		"description": "",
		"visibility": "private",
	}}

	policy.violation == {{"id": "missing_description"}} with input as inp
}

test_public_repo_violation if {
	inp := {"settings": {
		"archived": false,
		"description": "Open source project",
		"visibility": "public",
	}}

	policy.violation == {{"id": "unexpected_public_visibility"}} with input as inp
}

# policy_data can allow-list public repositories, clearing that violation.
test_public_repo_allowed_via_policy_data if {
	inp := {"settings": {
		"archived": false,
		"description": "Open source project",
		"visibility": "public",
	}}

	count(policy.violation) == 0 with input as inp
		with data.custom.allow_public_repositories as true
}

# Multiple breaches are reported together.
test_multiple_violations if {
	inp := {"settings": {
		"archived": true,
		"description": "",
		"visibility": "public",
	}}

	policy.violation == {
		{"id": "repo_archived"},
		{"id": "missing_description"},
		{"id": "unexpected_public_visibility"},
	} with input as inp
}
