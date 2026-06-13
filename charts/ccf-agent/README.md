# ccf-agent Helm chart

Deploys the CCF **compliance agent** — a scheduler that:

1. Reads plugin configuration from `/etc/ccf/config.yml` (rendered from a Secret)
2. Downloads plugin and policy OCI artifacts
3. Runs plugins on cron schedules
4. Reports heartbeats and evidence to the CCF API

Image: `ghcr.io/compliance-framework/agent`

## Install (standalone)

```bash
helm upgrade --install ccf-agent . -n ccf \
  -f values-production.yaml \
  -f ../../values/plugins/github.yaml \
  --set-string config.plugins.github_repos.config.token="$GITHUB_TOKEN"
```

> **At least one plugin is required** or the agent panics at startup.

## Key values

| Key | Description |
|-----|-------------|
| `apiUrl` | CCF API URL (default `http://ccf-api:8080`) |
| `config.plugins` | Plugin definitions (source, policies, schedule, config) |
| `config.daemon` | Long-running scheduler (`true`) |
| `extraEnv` / `extraEnvFrom` | Optional API auth env vars |

Plugin overlays live in [`values/plugins/`](../../values/plugins/).

## Config example

```yaml
config:
  plugins:
    github_repos:
      schedule: "*/30 * * * *"
      source: ghcr.io/compliance-framework/plugin-github-repositories:v0.8.1
      policies:
        - ghcr.io/compliance-framework/plugin-github-repositories-policies:v0.7.0
      config:
        organization: my-org
        token: ""    # inject via --set-string
```

In the umbrella chart, prefix keys with `ccf-agent.`.

## Full documentation

- [Plugins & policies guide](../../docs/policies-and-plugins.md)
- [Helm configuration — agent section](../../docs/helm-configuration.md#ccf-agent--agent--plugins)
- [Architecture](../../docs/architecture.md)
