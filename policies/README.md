# Custom CCF policies

CCF validates the evidence collected by plugins against **policies written in
Rego** (OPA). Policies are distributed as **OCI bundles** and referenced from
the agent config under `ccf-agent.config.plugins.<plugin>.policies`. The agent
pulls the bundle on its schedule and passes it to the plugin, which reports a
finding for every `violation`.

This directory is a self-contained example of authoring, testing, bundling and
shipping **your own** policies, mirroring the layout of the upstream
`*-policies` repos (e.g. `compliance-framework/plugin-github-repositories-policies`).

```
policies/
├── custom_repo_baseline.rego        example policy (GitHub repositories plugin)
├── custom_repo_baseline_test.rego   opa unit tests for the policy
└── README.md
```

## Authoring

A policy is a Rego file whose package starts with `compliance_framework.` and
exposes:

- `violation[...] if { ... }` — one entry per detected breach. Empty set = pass.
- `title`, `description`, `remarks` — human-readable metadata for the report.
- `risk_templates` — optional structured risk/remediation metadata (OSCAL-style).

The plugin feeds the collected evidence in as `input`. Inspect the matching
plugin's docs (or its `*-policies` repo tests) to learn the `input` shape.

## Test, validate, bundle, push

All wired into the repo `Makefile` (run from the repo root). They use the same
toolchain as upstream: `opa` for testing/bundling and
[`gooci`](https://github.com/compliance-framework/gooci) to push the bundle to
an OCI registry.

```bash
make policy-test       # opa test ./policies  (unit tests)
make policy-validate   # opa check ./policies (compile/type check)
make policy-build      # opa build -> dist/policies-bundle.tar.gz
make policy-push \      # push the bundle to your registry (read/write creds)
  POLICY_IMAGE=ghcr.io/<your-org>/ccf-custom-policies:v0.1.0 \
  GHCR_USER=<user> GHCR_TOKEN=$GHCR_TOKEN
```

## Use it in CCF

Reference the pushed bundle from a plugin in your agent config. The
`values/plugins/custom-policies.yaml` overlay shows this layered on top of the
GitHub plugin:

```yaml
ccf-agent:
  config:
    plugins:
      github_repos:
        policies:
          - ghcr.io/compliance-framework/plugin-github-repositories-policies:v0.7.0
          - ghcr.io/<your-org>/ccf-custom-policies:v0.1.0   # <- your bundle
```

Then deploy with the overlay layered on, e.g.:

```bash
make up PLUGIN_VALUES="values/plugins/github.yaml values/plugins/custom-policies.yaml" \
  GITHUB_TOKEN=$GITHUB_TOKEN GITHUB_ORG=<your-org>
```
