# ccf-agent Helm chart

CCF **agent** — plugin scheduler that collects evidence and reports to the API.

| | |
|---|---|
| Image | `ghcr.io/compliance-framework/agent:0.7.1` |
| Requires | CCF API ≥ 0.13.0 (repo pins API 0.16.0) |
| Requires | At least one plugin in `config.plugins` |

Prefer the umbrella install: `make up` (local) or `make prod` (production).

## Configuration

Plugin config is rendered to a **Secret** at `/etc/ccf/config.yml`. Define plugins under `ccf-agent.config.plugins` in the environment overlay:

- Local: [`values/local.yaml`](../../values/local.yaml) — `local-ssh` plugin
- Production: [`values/production.yaml`](../../values/production.yaml) — GitHub plugin

```yaml
config:
  daemon: true
  plugins:
    github_repos:
      source: ghcr.io/compliance-framework/plugin-github-repositories:v0.8.1
      schedule: "*/30 * * * *"
      policies:
        - ghcr.io/compliance-framework/plugin-github-repositories-policies:v0.7.0
      config:
        organization: my-org
        token: ""   # inject: GITHUB_TOKEN / --set-string
```

## Documentation

- [Plugins & policies](../../docs/policies-and-plugins.md)
- [Production](../../docs/production.md)
