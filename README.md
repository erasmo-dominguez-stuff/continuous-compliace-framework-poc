# CCF Helm Charts

Helm charts to deploy the [Continuous Compliance Framework (CCF)](https://continuouscompliance.io/)
on Kubernetes.

CCF is an open source, automated compliance testing and reporting system that
helps organizations continuously assess adherence to standards such as
NIST SP 800-53, SOC 2, PCI DSS and GDPR, producing OSCAL-compliant reports.

## Chart structure

Charts are split **by lifecycle**, not by container:

```
ccf/                       umbrella chart (depends on the two below)
└── charts/
    ├── ccf-app/           control plane: PostgreSQL + API + UI
    └── ccf-agent/         compliance agent (deploy independently, possibly many)
```

- **`ccf-app`** is a cohesive control plane (the UI, API and DB share a release
  and version). Deploy once.
- **`ccf-agent`** has a different lifecycle: it is distributed and typically
  deployed many times, in different namespaces/clusters/edge, each with its own
  plugin set, decoupled from the control-plane release.
- **`ccf`** (umbrella) composes both for a single-command install (dev / simple
  setups). For production GitOps, prefer deploying the subcharts as independent
  Argo CD Applications.

| Component  | Chart       | Image                                  | Purpose                          |
|------------|-------------|----------------------------------------|----------------------------------|
| PostgreSQL | `ccf-app`   | `ghcr.io/compliance-framework/pg-ccf`  | Datastore / source of truth      |
| API        | `ccf-app`   | `ghcr.io/compliance-framework/api`     | Central OSCAL reporting API      |
| UI         | `ccf-app`   | `ghcr.io/compliance-framework/ui`      | Web frontend                     |
| Agent      | `ccf-agent` | `ghcr.io/compliance-framework/agent`   | Scheduler/orchestrator of plugins|

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- A default StorageClass (for the PostgreSQL PVC) when `postgres.persistence.enabled=true`

For a local cluster you can use either:

- **`kind`** (`kind` + `kubectl` + `helm`), or
- **Docker Desktop Kubernetes** (`docker` with Kubernetes enabled + `kubectl` + `helm`).

Both are driven by the `Makefile` (see [Local deployment](#local-deployment)).

## Install

Full stack via the umbrella (one command):

```bash
helm install ccf . --namespace ccf --create-namespace -f values-local.yaml
```

Independently (recommended for production):

```bash
helm install ccf-app   charts/ccf-app   -n ccf --create-namespace \
  -f charts/ccf-app/values-production.yaml
helm install ccf-agent charts/ccf-agent -n ccf \
  -f charts/ccf-agent/values-production.yaml
```

> Values are **top-level** in each subchart (e.g. `api.replicaCount`), and
> **namespaced** in the umbrella (e.g. `ccf-app.api.replicaCount`).

## Local deployment

The `Makefile` wraps the full local flow and supports **two local Kubernetes
runtimes** via the `RUNTIME` variable:

| `RUNTIME` | Cluster                          | kube-context     |
|-----------|----------------------------------|------------------|
| `kind`    | local `kind` cluster (default)   | `kind-ccf`       |
| `docker`  | Docker Desktop Kubernetes        | `docker-desktop` |

Every `helm`/`kubectl` command issued by the `Makefile` is pinned to the
selected context, so you never deploy to the wrong cluster by accident.

### Option A — kind (default)

Requires `kind`, `kubectl`, `helm`:

```bash
make up        # create cluster + helm install with values-local.yaml
make pf        # port-forward UI (8000) and API (8080)
```

### Option B — Docker Desktop Kubernetes

Requires Docker Desktop with Kubernetes enabled
(**Settings → Kubernetes → Enable Kubernetes**), plus `kubectl` and `helm`:

```bash
make up-docker  # verify the docker-desktop context + helm install
make pf-docker  # port-forward UI (8000) and API (8080)
```

`make up-docker` is shorthand for `make RUNTIME=docker up`; any target accepts
the `RUNTIME=docker` override (e.g. `make RUNTIME=docker status`). It checks
that the `docker-desktop` context exists and is reachable before installing, so
you get a clear error if Kubernetes is not enabled in Docker Desktop.

### After it's up (both options)

Open http://localhost:8000. The UI talks to the API at `http://localhost:8080`
(`ui.apiUrl` in `values-local.yaml`), matching the port-forward.

`values-local.yaml` disables persistence and trims resources for laptops; it
works unchanged on both runtimes. Tear down with:

```bash
make down         # kind: uninstall release + delete the cluster
make down-docker  # docker: uninstall release (cluster keeps running)
```

> The bundled `helm dependency build` step (subchart vendoring) runs
> automatically before every install via the `deps` target.

## Quick local access (no ingress)

```bash
kubectl -n ccf port-forward svc/ccf-ui 8000:80
kubectl -n ccf port-forward svc/ccf-api 8080:8080
```

## Expose with ingress

```yaml
ingress:
  enabled: true
  className: nginx
  uiHost: ccf.example.com
  apiHost: api.ccf.example.com
  tls:
    - hosts: [ccf.example.com, api.ccf.example.com]
      secretName: ccf-tls
```

When ingress hosts are set, the UI's `API_URL` and the API's allowed CORS
origins are derived automatically from those hosts.

## Using an external database

```yaml
postgres:
  enabled: false
api:
  database:
    host: my-postgres.example.com
    # or provide a full connection string:
    # connection: "host=... user=... password=... dbname=ccf port=5432 sslmode=require"
```

> Note for the umbrella: the agent reaches the API via `ccf-agent.apiUrl`.
> `ccf-app.fullnameOverride: ccf` makes the API service `ccf-api`, which the
> default `ccf-agent.apiUrl` (`http://ccf-api:8080`) targets.

## Key values

`ccf-app` (top-level in the subchart; prefix with `ccf-app.` in the umbrella):

| Key                          | Default                                  | Description                                  |
|------------------------------|------------------------------------------|----------------------------------------------|
| `postgres.enabled`           | `true`                                   | Deploy bundled PostgreSQL                    |
| `postgres.auth.password`     | `postgres`                               | DB password (change for non-local)           |
| `postgres.auth.existingSecret` | `""`                                   | Use an existing DB credentials Secret        |
| `postgres.persistence.size`  | `8Gi`                                    | PVC size for the database                    |
| `api.environment`            | `production`                             | `local` disables HTTPS-only behaviours       |
| `api.database.existingSecret`| `""`                                     | Secret with `CCF_DB_CONNECTION`              |
| `api.metrics.enabled`        | `true`                                   | Expose Prometheus `/metrics` on `:9090`      |
| `ui.apiUrl`                  | `""` (derived)                           | API URL as seen by the browser               |
| `ingress.enabled`            | `false`                                  | Create an Ingress for UI/API                 |
| `networkPolicy.enabled`      | `false`                                  | Restrict pod-to-pod traffic                  |

`ccf-agent` (top-level; prefix with `ccf-agent.` in the umbrella):

| Key            | Default                  | Description                                |
|----------------|--------------------------|--------------------------------------------|
| `apiUrl`       | `http://ccf-api:8080`    | CCF API endpoint the agent reports to      |
| `config`       | minimal                  | Rendered to `/etc/ccf/config.yml`          |
| `config.plugins` | `{}`                   | Plugins/policies to schedule               |

## GitOps with Argo CD

Manifests live in [`argocd/`](./argocd):

| File                        | Purpose                                                      |
|-----------------------------|-------------------------------------------------------------|
| `project.yaml`              | `AppProject` scoping repos/namespaces                       |
| `ccf-app-application.yaml`  | `ccf-app` chart (control plane)                             |
| `ccf-agent-application.yaml`| `ccf-agent` chart (independent lifecycle)                   |
| `alloy-application.yaml`    | Grafana Alloy (multi-source: chart + values from this repo) |
| `root-application.yaml`     | App-of-apps that deploys the above                          |

Bootstrap everything with a single apply:

```bash
kubectl apply -n argocd -f argocd/root-application.yaml
```

> Update `repoURL` / `targetRevision` (`main` by default) in each file to match
> your fork and branch.

## Observability with Grafana Alloy

All CCF workloads carry the label `app.kubernetes.io/part-of=ccf`, and the API
pods are annotated for Prometheus scraping (`/metrics` on port `9090`,
controlled by `api.metrics`). [`observability/alloy-values.yaml`](./observability/alloy-values.yaml)
configures Grafana Alloy to:

- **Logs**: stream container logs of all `part-of=ccf` pods to Loki.
- **Metrics**: scrape pods annotated `prometheus.io/scrape=true` and
  `remote_write` them to a Prometheus-compatible backend.

Install (with an optional local Loki + Prometheus stack for testing):

```bash
make obs-stack   # minimal Loki + Prometheus in the observability namespace
make obs-alloy   # Grafana Alloy collecting CCF logs & metrics
```

Edit the two endpoint URLs at the bottom of `alloy-values.yaml` to point at your
own Loki / Prometheus (or Grafana Cloud) backends.

## Production checklist

Critical items addressed by `values-production.yaml` (review every `CHANGE-ME`):

- **Secrets**: no plaintext DB password. Create the credential Secrets first:

  ```bash
  kubectl create secret generic ccf-postgres-credentials -n ccf \
    --from-literal=POSTGRES_USER=ccf \
    --from-literal=POSTGRES_PASSWORD='<strong-password>' \
    --from-literal=POSTGRES_DB=ccf

  # The API only takes a single connection string, kept in sync with the above:
  kubectl create secret generic ccf-db-connection -n ccf \
    --from-literal=CCF_DB_CONNECTION='host=ccf-postgres user=ccf password=<strong-password> dbname=ccf port=5432 sslmode=require'
  ```

  The chart fails fast if `postgres.auth.existingSecret` is set without a
  matching `api.database.existingSecret`/`connection`.
- **Agent plugins**: the agent **fails to start with no plugins configured**
  (`panic: no plugins specified in config`). Configure at least one plugin under
  `ccf-agent.config.plugins` (see `values-local.yaml` for a working example),
  or set `ccf-agent.enabled=false` if you only need the control plane.
- **High availability**: API/UI run 2+ replicas with pod anti-affinity, HPA and
  PodDisruptionBudgets.
- **Database**: the bundled PostgreSQL is a single replica with no backups —
  for real workloads use a managed DB (`postgres.enabled=false`) with HA/backups.
- **Network isolation**: `networkPolicy.enabled=true` restricts traffic
  (only the API reaches PostgreSQL; only ingress/UI/Alloy reach the API).
- **Pod hardening**: non-root, dropped capabilities and `RuntimeDefault` seccomp
  via `securityContext` / `podSecurityContext`.
- **TLS**: ingress with cert-manager annotations and TLS hosts.
- **Resources**: requests/limits set per component.
- **Observability**: API metrics enabled and scraped by Alloy.

Install in production (per-subchart `values-production.yaml`):

```bash
helm upgrade --install ccf-app   charts/ccf-app   -n ccf --create-namespace \
  -f charts/ccf-app/values-production.yaml
helm upgrade --install ccf-agent charts/ccf-agent -n ccf \
  -f charts/ccf-agent/values-production.yaml
```

## Uninstall

```bash
# umbrella
helm uninstall ccf -n ccf
# or per-subchart
helm uninstall ccf-agent ccf-app -n ccf
```

> Note: An official set of charts (`ccf-app`, `ccf-agent`) is also maintained at
> https://github.com/compliance-framework/helm-charts. These charts are an
> independent implementation following the same lifecycle split, with batteries
> included (local kind flow, Argo CD apps and Grafana Alloy observability).
