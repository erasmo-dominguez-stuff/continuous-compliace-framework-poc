# ccf-agent Helm chart

Standard CCF **agent** chart — the plugin scheduler that collects evidence and reports to the API.

| | |
|---|---|
| **CCF role** | Runs plugins on a cron schedule; sends heartbeats, evidence, and templates to the API |
| **Image** | `ghcr.io/compliance-framework/agent:0.7.1` |
| **Requires** | CCF API ≥ 0.13.0 (this repo pins API 0.16.0) |
| **Requires** | At least one plugin in `config.plugins` |

## Install (standalone)

```bash
helm upgrade --install ccf-agent . -n ccf \
  -f values-production.yaml \
  -f ../../values/plugins/github.yaml \
  --set-string config.plugins.github_repos.config.token="$GITHUB_TOKEN" \
  --set-string config.plugins.github_repos.config.organization="$GITHUB_ORG"
```

## Production profile

`values-production.yaml` includes:

- PodDisruptionBudget
- Resource requests/limits
- Pod security (non-root, read-only root FS, dropped caps)
- `verbosity: 1` (less noisy than local)

Deploy **one agent release per estate**. Scale by adding separate releases with different plugins — not by increasing `replicaCount` on the same config.

## Configuration

Plugin and policy config is rendered to a **Secret** mounted at `/etc/ccf/config.yml`:

```yaml
config:
  daemon: true
  plugins:
    github_repos:
      source: ghcr.io/compliance-framework/plugin-github-repositories:0.1.0
      schedule: "0 * * * *"
      policies:
        - source: ghcr.io/compliance-framework/plugin-github-repositories-policies:0.1.0
      config:
        organization: my-org
        token: ""   # inject via --set-string
```

Layer reusable overlays from [`values/plugins/`](../../values/plugins/).

## Observability

The agent does **not** expose `/metrics`. Monitor via:

- **Logs** — Loki / `kubectl logs` (plugin errors, heartbeat failures)
- **Pod metrics** — CPU, memory, restarts via Prometheus/kube-state-metrics
- **API** — agent heartbeats visible in UI and API

## Documentation

- [Components explained](../../docs/components.md) — agent vs plugin vs policy
- [Plugins & policies](../../docs/policies-and-plugins.md)
- [Production deployment](../../docs/production.md)
