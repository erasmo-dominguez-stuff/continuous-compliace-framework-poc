# ccf-app Helm chart

Standard CCF **control plane** chart — the central compliance platform:

| Component | CCF role | Image |
|-----------|----------|-------|
| **PostgreSQL** | OSCAL + evidence datastore | `ghcr.io/compliance-framework/pg-ccf` |
| **API** | Reporting service, auth, agent ingestion | `ghcr.io/compliance-framework/api:0.16.0` |
| **UI** | Operator console | `ghcr.io/compliance-framework/ui:2.9.1` |

The **agent** (plugin scheduler) is a separate chart: [`ccf-agent`](../ccf-agent/).

## Install (standalone)

```bash
# Production (Secrets required first — see values-production.yaml)
helm upgrade --install ccf-app . -n ccf --create-namespace \
  -f values-production.yaml

# Local / dev
helm upgrade --install ccf-app . -n ccf --create-namespace \
  --set-string api.adminUser.password='Admin12345!'
```

## Production profile

| File | Purpose |
|------|---------|
| `values-production.yaml` | 2 replicas, PDB, HPA, ingress, networkPolicy, metrics |
| Umbrella [`values/production.yaml`](../../values/production.yaml) | Same settings under `ccf-app.*` prefix |

Reliability features included:

- PodDisruptionBudgets (API, UI)
- HorizontalPodAutoscaler (API)
- Pod anti-affinity
- NetworkPolicy (ingress + monitoring namespaces)
- Prometheus metrics on `:9090/metrics`
- Secure defaults (non-root, dropped capabilities)

## Key values

| Area | Keys |
|------|------|
| Database | `postgres.*`, `api.database.*` |
| Auth / users | `api.adminUser.*`, `api.migrations.enabled` |
| Demo OSCAL | `api.seedData.enabled` + files in `seed/oscal/` |
| UI | `ui.apiUrl`, `ui.image.tag` |
| Ingress | `ingress.*` |
| Hardening | `networkPolicy.*`, `api.metrics.*`, `api.pdb`, `api.autoscaling` |

Values are **top-level** in this chart (`api.replicaCount`). In the umbrella chart, prefix with `ccf-app.`.

## Hooks

| Job | When | Purpose |
|-----|------|---------|
| migrate initContainer | API pod start | `/api migrate up` |
| admin-bootstrap | post-install/upgrade | Create default admin |
| seed | post-install/upgrade | Import OSCAL demo data |

## Documentation

- [Components explained](../../docs/components.md) — what API, UI, Postgres mean in CCF
- [Production deployment](../../docs/production.md) — secrets, HA, alerts, runbook
- [Helm configuration](../../docs/helm-configuration.md)
- [Architecture](../../docs/architecture.md)
