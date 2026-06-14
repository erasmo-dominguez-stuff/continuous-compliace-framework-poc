# Helm configuration guide

This guide covers how to install, layer values, and configure every major option in the CCF Helm charts.

## Chart hierarchy

```mermaid
flowchart TB
    UMB["ccf/ umbrella chart"]
    APP["ccf-app/<br/>PostgreSQL + API + UI"]
    AGT["ccf-agent/<br/>plugin scheduler"]

    UMB --> APP
    UMB --> AGT
```

### Values namespacing

| Install target | Values prefix | Example |
|----------------|---------------|---------|
| Umbrella `ccf` | `ccf-app.*`, `ccf-agent.*` | `ccf-app.api.replicaCount: 2` |
| Subchart `ccf-app` | top-level keys | `api.replicaCount: 2` |
| Subchart `ccf-agent` | top-level keys | `config.plugins.github_repos...` |

Helm **deep-merges** multiple `-f` files. Later files override earlier keys.

## Image registry and tags

Component images are configured **in each subchart** — no separate mirror file.

| Chart | Values path | Default |
|-------|-------------|---------|
| `ccf-app` | `images.registry`, `images.api/ui/postgres.*` | `ghcr.io/compliance-framework/...` |
| `ccf-agent` | `images.registry`, `images.agent.*` | `ghcr.io/compliance-framework/agent:0.7.1` |

Plugin OCI refs in agent config keep upstream paths; the agent chart rewrites them when `images.pluginRegistry` (or `images.registry`) differs.

```yaml
# Mirror everything to Artifactory (umbrella install)
ccf-app:
  images:
    registry: artifactory.example.com/docker-remote/compliance-framework
    pluginRegistry: artifactory.example.com/docker-remote/compliance-framework
ccf-agent:
  images:
    registry: artifactory.example.com/docker-remote/compliance-framework
    pluginRegistry: artifactory.example.com/docker-remote/compliance-framework
```

Or one Makefile flag:

```bash
make up REGISTRY_PREFIX=artifactory.example.com/docker-remote/compliance-framework
```

Per-component override:

```yaml
ccf-app:
  api:
    image:
      repository: my.registry.example.com/custom/ccf-api
      tag: "0.16.0"
```

### Values layering

```mermaid
flowchart LR
    V0["values.yaml<br/>umbrella defaults"]
    V1["values/local.yaml<br/>values/aks.yaml<br/>values/production.yaml"]
    V2["--set-string secrets<br/>ADMIN_PASSWORD · GITHUB_TOKEN"]
    V3["REGISTRY_PREFIX<br/>SEED=1<br/>(optional)"]

    V0 --> V1 --> V2 --> V3
    V3 --> HELM["helm upgrade --install ccf ."]
```

**Three environment overlays** — plugins in `values/plugins/` layered via `PLUGIN_VALUES`:

| File | Command | Contents |
|------|---------|----------|
| `values/local.yaml` | `make up` | Demo admin, seed, agent register |
| `values/aks.yaml` | `make aks` | AKS smoke test |
| `values/production.yaml` | `make prod` | HA, ingress, networkPolicy |

| Plugin overlay | Default for |
|----------------|-------------|
| `values/plugins/local-ssh.yaml` | `make up`, `make aks` |
| `values/plugins/github.yaml` | `make prod` |
| `values/plugins/custom-policies.yaml` | Optional — layer after `github.yaml` |

See [values/plugins/README.md](../values/plugins/README.md).

Secrets at install time via Makefile variables (never commit):

```bash
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='your-org'
make aks ADMIN_PASSWORD='...'
```

## Environment overlays

### `values/local.yaml` (Docker Desktop)

| Setting | Purpose |
|---------|---------|
| API/UI **2 replicas** + PDB | Same HA baseline as production (survives pod restarts) |
| Postgres persistence off | Faster reset on laptops |
| `seedData.enabled: true` | Demo OSCAL so UI is not empty |
| Inline admin password | Local-only login (`admin@ccf.local`) |
| Metrics on | Works with `make obs` |
| `postgres.persistence.enabled: false` | No PVC on laptop |
| `api.environment: local` | Relaxed HTTPS behaviour |
| `api.allowedOrigins` | CORS for `localhost:8000` / `:8080` |
| `ui.apiUrl: http://localhost:8080` | Browser reaches API via port-forward |
| `api.adminUser.enabled: true` | Default admin bootstrap |
| `networkPolicy.enabled: false` | Simpler local networking |

### `values/aks.yaml` (AKS smoke test)

| Setting | Purpose |
|---------|---------|
| Single replica API/UI | Faster, cheaper validation |
| `postgres.persistence.storageClass: managed-csi` | Azure Disk |
| Same bootstrap as local | admin, seed, agent register, local-ssh plugin |
| `adminUser.password: ""` | Inject via `make aks ADMIN_PASSWORD='...'` |

### `values/production.yaml`

| Setting | Purpose |
|---------|---------|
| HA API/UI + HPA + PDB | Production reliability |
| Ingress + TLS + NetworkPolicy | External access hardening |
| GitHub plugin in `ccf-agent.config.plugins` | Token/org via `GITHUB_TOKEN` / `GITHUB_ORG` |
| `agentRegister` + auth Secret | Agent visible in Admin → Agents |
| `seedData.enabled: false` | Import your own OSCAL |

## `ccf-app` — control plane

### PostgreSQL (`postgres.*`)

| Key | Default | Description |
|-----|---------|-------------|
| `postgres.enabled` | `true` | Deploy bundled StatefulSet |
| `postgres.auth.password` | `postgres` | DB password (change for non-local) |
| `postgres.auth.existingSecret` | `""` | Secret with `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` |
| `postgres.persistence.enabled` | `true` | PVC for data |
| `postgres.persistence.storageClass` | `""` | Cluster default if empty |
| `postgres.persistence.size` | `8Gi` | Volume size |

When using an external database:

```yaml
ccf-app:
  postgres:
    enabled: false
  api:
    database:
      host: my-postgres.example.com
      # or full connection string:
      connection: "host=... user=ccf password=... dbname=ccf sslmode=require"
```

### API (`api.*`)

| Key | Default | Description |
|-----|---------|-------------|
| `api.image.tag` | Chart `appVersion` (`0.16.0`) | API image tag |
| `api.environment` | `production` | Set `local` for dev |
| `api.allowedOrigins` | auto / empty | CORS origins (comma-separated) |
| `api.migrations.enabled` | `true` | Init container runs `/api migrate up` |
| `api.metrics.enabled` | `true` | Prometheus `/metrics` on port 9090 |
| `api.database.existingSecret` | `""` | Secret key `CCF_DB_CONNECTION` |
| `api.jwtSecret` | generated | JWT signing (or existing Secret) |

#### Admin bootstrap (`api.adminUser.*`)

Post-install Job creates the first UI user (idempotent):

```yaml
ccf-app:
  api:
    adminUser:
      enabled: true
      email: admin@ccf.local
      firstName: Admin
      lastName: User
      password: ""              # --set-string at install
      existingSecret: ""        # or Secret with key `password`
```

Makefile: `ADMIN_PASSWORD='...'` enables and injects the password.

#### Demo OSCAL seed (`api.seedData.enabled`)

Imports bundled JSON from `charts/ccf-app/seed/oscal/` in order:

1. `basic-catalog.json`
2. `goodread_ssp.json`
3. `goodread_ap.json`
4. `goodread_ar.json`
5. `goodread_poam.json`

Makefile: `SEED=1` or `--set ccf-app.api.seedData.enabled=true`

### UI (`ui.*`)

| Key | Default | Description |
|-----|---------|-------------|
| `ui.image.tag` | `2.9.1` | UI image (must match API generation) |
| `ui.apiUrl` | derived from ingress or empty | Written to `config.json` as `API_URL` |

For port-forward access, set `ui.apiUrl` to `http://localhost:8080` (as in `values/local.yaml`).

### Ingress (`ingress.*`)

```yaml
ccf-app:
  ingress:
    enabled: true
    className: nginx
    uiHost: ccf.example.com
    apiHost: api.ccf.example.com
    tls:
      - hosts: [ccf.example.com, api.ccf.example.com]
        secretName: ccf-tls
```

When hosts are set, CORS and UI `API_URL` are derived automatically.

### Network policies (`networkPolicy.*`)

Set `networkPolicy.enabled: true` in production to restrict:

- Only API → PostgreSQL
- Ingress/UI/Alloy → API
- Monitoring namespace → API metrics port

### Helm tests (`tests.*`)

`tests.enabled: true` installs a `helm test` hook Pod that curls API and UI in-cluster.

## `ccf-agent` — agent & plugins

| Key | Default | Description |
|-----|---------|-------------|
| `apiUrl` | `http://ccf-api:8080` | API endpoint (override if API elsewhere) |
| `config.daemon` | `true` | Run as long-lived scheduler |
| `config.verbosity` | `2` | Log level |
| `config.plugins` | `{}` | **Required**: at least one plugin |
| `extraEnv` / `extraEnvFrom` | `[]` | Optional env for API auth (`CCF_API_AUTH_*`) |

Plugin structure (rendered to Secret → `/etc/ccf/config.yml`):

```yaml
ccf-agent:
  config:
    plugins:
      <plugin_key>:
        schedule: "0 * * * *"          # cron
        source: ghcr.io/.../plugin:tag # OCI plugin binary
        policies:                       # OCI Rego bundles (one or more)
          - ghcr.io/.../policies:tag
        labels:                         # metadata on evidence
          team: platform
        config:                          # plugin-specific (may include secrets)
          organization: my-org
          token: ""
        policy_data:                     # optional Rego `data.custom.*`
          allow_public_repositories: false
```

**Disable agent only:**

```yaml
ccf-agent:
  enabled: false
```

## Helm hooks (Jobs)

```mermaid
sequenceDiagram
    participant H as Helm install/upgrade
    participant M as migrate initContainer
    participant API as ccf-api Deployment
    participant ADM as admin-bootstrap Job
    participant SEED as seed Job

    H->>M: API pod starts
    M->>M: /api migrate up
    H->>API: roll out API/UI/agent
    H->>ADM: post-install hook (weight 5)
    ADM->>ADM: /api users add
    H->>SEED: post-install hook (weight 10, if SEED enabled)
    SEED->>SEED: /api oscal import (catalog → SSP → AP → AR → POA&M)
```

| Hook | Weight | Trigger | Purpose |
|------|--------|---------|---------|
| `ccf-api-admin-bootstrap` | 5 | post-install/upgrade | Create default admin user |
| `ccf-api-agent-register` | 6 | post-install/upgrade | Register agent + auth Secret |
| `ccf-api-seed` | 10 | post-install/upgrade | Import OSCAL demo data |
| `ccf-test-connection` | test | `helm test` | Connectivity check |

Hooks delete successful Jobs (`hook-succeeded`) so they do not clutter the namespace.

## Secrets injection (never in git)

| Secret | Makefile variable | Helm `--set-string` |
|--------|-------------------|---------------------|
| GitHub token | `GITHUB_TOKEN` | `ccf-agent.config.plugins.github_repos.config.token` |
| GitHub org | `GITHUB_ORG` | `ccf-agent.config.plugins.github_repos.config.organization` |
| Admin password | `ADMIN_PASSWORD` | `ccf-app.api.adminUser.password` |

Add local secret-bearing files to `.gitignore` if you create custom value files.

## Production install

```bash
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='your-org'
```

See [`production.md`](./production.md) for required Kubernetes Secrets.

## Validation before deploy

```bash
make validate     # lint + render local, aks, production
make loadtest-smoke   # k6 API smoke (after make pf)
helm template ccf . -f values/production.yaml \
  --set-string ccf-app.api.adminUser.password=dummy \
  | less
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Login fails / no users table | Migrations disabled | `api.migrations.enabled: true` or run `/api migrate up` |
| Agent CrashLoop / panic | No plugins | Add plugin overlay or `ccf-agent.enabled: false` |
| Plugin 404 on subject templates | API too old | Upgrade API to ≥ 0.13 (this repo: 0.16.0) |
| UI empty catalogs/plans | No OSCAL import | `SEED=1` or manual `oscal import` |
| UI can't reach API | Wrong `ui.apiUrl` | Match port-forward URL (`http://localhost:8080`) |
| GitHub plugin auth errors | Missing token | Pass `GITHUB_TOKEN` at install |

API Swagger (after port-forward): http://localhost:8080/swagger/index.html
