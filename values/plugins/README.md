# Plugin overlays

CCF **plugins are not separate Helm charts**. They are OCI binaries pulled by the **ccf-agent** at runtime. This folder holds reusable value overlays that configure `ccf-agent.config.plugins`.

## Layout

| File | Plugin | Use with |
|------|--------|----------|
| `local-ssh.yaml` | `plugin-local-ssh` | `make up`, `make aks` (default) |
| `github.yaml` | `plugin-github-repositories` | `make prod` + `GITHUB_TOKEN` / `GITHUB_ORG` |
| `custom-policies.yaml` | Custom Rego bundle on GitHub plugin | After `make policy-push` — layer **after** `github.yaml` |

## Examples

```bash
# Local demo (default plugin)
make up

# GitHub org scan (production)
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='my-org'

# GitHub + your custom policy bundle
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='my-org' \
  PLUGIN_VALUES="values/plugins/github.yaml values/plugins/custom-policies.yaml"

# Local GitHub demo
make up PLUGIN_VALUES=values/plugins/github.yaml GITHUB_TOKEN='...' GITHUB_ORG='my-org'
```

Secrets (`token`, `organization`) are injected via Makefile — never commit them.

## Custom policies workflow

1. Edit Rego in [`policies/`](../../policies/)
2. `make policy && make policy-push POLICY_IMAGE=ghcr.io/you/ccf-custom-policies:v0.1.0 ...`
3. Set that image in `custom-policies.yaml` under `plugins.github_repos.policies`
4. Layer `github.yaml` + `custom-policies.yaml` (see above)

**Note:** Helm replaces YAML arrays on merge. `custom-policies.yaml` lists the **full** `policies[]` (upstream + custom) so it must be the last plugin overlay when combined with `github.yaml`.

## Multiple agents (advanced)

One agent release = one plugin schedule config. To run different plugins on different estates, deploy **separate agent releases** (different namespace or `fullnameOverride`), each with its own plugin overlay — not separate plugin Helm charts.
