# ccf-app Helm chart

Standard CCF **control plane** chart — PostgreSQL, API, and UI.

| Component | Image |
|-----------|-------|
| PostgreSQL | `ghcr.io/compliance-framework/pg-ccf` |
| API | `ghcr.io/compliance-framework/api:0.16.0` |
| UI | `ghcr.io/compliance-framework/ui:2.9.1` |

The agent is a separate chart: [`ccf-agent`](../ccf-agent/). Prefer the umbrella install with [`values/local.yaml`](../../values/local.yaml) or [`values/production.yaml`](../../values/production.yaml).

## Install (umbrella — recommended)

```bash
helm dependency build ../..
helm upgrade --install ccf ../.. -n ccf --create-namespace -f ../../values/local.yaml
```

## Key values

| Area | Keys |
|------|------|
| Database | `postgres.*`, `api.database.*` |
| Auth / users | `api.adminUser.*`, `api.agentRegister.*` |
| Demo OSCAL | `api.seedData.enabled` + `seed/oscal/` |
| UI | `ui.apiUrl`, `ui.replicaCount` |
| Ingress | `ingress.*` |
| Hardening | `networkPolicy.*`, `api.metrics.*`, `api.pdb`, `api.autoscaling` |

In the umbrella chart, prefix keys with `ccf-app.`.

## Hooks

| Job | Purpose |
|-----|---------|
| migrate initContainer | `/api migrate up` |
| admin-bootstrap | Create default admin |
| agent-register | Register agent + auth Secret |
| seed | Import OSCAL demo data |

## Documentation

- [Quick start](../../docs/quickstart.md)
- [Production](../../docs/production.md)
- [Helm configuration](../../docs/helm-configuration.md)
