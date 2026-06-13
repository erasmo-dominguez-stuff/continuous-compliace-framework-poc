# ccf-app Helm chart

Deploys the CCF **control plane**:

- **PostgreSQL** — datastore (`ghcr.io/compliance-framework/pg-ccf`)
- **API** — OSCAL reporting service (`ghcr.io/compliance-framework/api`)
- **UI** — web frontend (`ghcr.io/compliance-framework/ui`)

## Install (standalone)

```bash
helm upgrade --install ccf-app . -n ccf --create-namespace \
  -f values-production.yaml
```

Production: create DB/JWT Secrets first — see comments in `values-production.yaml`.

## Key values

| Area | Keys |
|------|------|
| Database | `postgres.*`, `api.database.*` |
| Auth / users | `api.adminUser.*`, `api.migrations.enabled` |
| Demo OSCAL | `api.seedData.enabled` + files in `seed/oscal/` |
| UI | `ui.apiUrl`, `ui.image.tag` |
| Ingress | `ingress.*` |
| Hardening | `networkPolicy.*`, `api.metrics.*` |

Values are **top-level** in this chart (`api.replicaCount`). In the umbrella chart, prefix with `ccf-app.`.

## Hooks

| Job | When | Purpose |
|-----|------|---------|
| migrate initContainer | API pod start | `/api migrate up` |
| admin-bootstrap | post-install/upgrade | Create default admin |
| seed | post-install/upgrade | Import OSCAL demo data |

## Full documentation

- [Helm configuration guide](../../docs/helm-configuration.md)
- [Architecture](../../docs/architecture.md)
- [Quick start](../../docs/quickstart.md)
