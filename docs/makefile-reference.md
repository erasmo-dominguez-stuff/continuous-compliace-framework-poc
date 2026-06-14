# Makefile reference

The `Makefile` automates local (Docker Desktop), AKS smoke test, and production deployments. Run `make help` for the public target list.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KUBE_CONTEXT` | `docker-desktop` | Context for local `helm`/`kubectl` |
| `NAMESPACE` | `ccf` | CCF release namespace |
| `OBS_NAMESPACE` | `observability` | Observability stack namespace |
| `RELEASE` | `ccf` | Helm release name |
| `ENV_LOCAL` | `values/local.yaml` | Local environment overlay |
| `ENV_AKS` | `values/aks.yaml` | AKS smoke-test overlay |
| `ENV_PROD` | `values/production.yaml` | Production overlay |
| `REGISTRY_PREFIX` | (empty) | Mirror all CCF images |
| `GITHUB_TOKEN` | (empty) | GitHub plugin token (prod / custom) |
| `GITHUB_ORG` | (empty) | GitHub organisation |
| `ADMIN_PASSWORD` | (empty) | Admin bootstrap password |
| `PLUGIN_VALUES` | (auto) | Space-separated plugin overlays; overrides defaults for any target |
| `PROD_PLUGIN_VALUES` | `values/plugins/github.yaml` | Default plugins for `make prod` when `PLUGIN_VALUES` is empty |
| `SEED` | (empty) | Set to `1` to force OSCAL seed (on by default in local/aks) |
| `LOADTEST_BASE_URL` | `http://localhost:8080` | k6 target API URL |
| `LOADTEST_ADMIN_EMAIL` | `admin@ccf.local` | k6 login email |
| `LOADTEST_ADMIN_PASSWORD` | `Admin12345!` | k6 login password |
| `K6_VUS` / `K6_DURATION` | `10` / `2m` | Load test intensity (see loadtest/README.md) |

## Headline targets

| Target | Description |
|--------|-------------|
| `make up` | Deploy CCF locally (`values/local.yaml`) |
| `make aks` | Deploy on current context (`values/aks.yaml`) |
| `make prod` | Production profile (`values/production.yaml`) |
| `make obs` | Loki + Prometheus + Grafana + Alloy |
| `make pf` | Port-forward UI :8000, API :8080 |
| `make pf-all` | Port-forward UI, API, Grafana, Prometheus, Loki |
| `make smoke` | Rollout wait + `helm test` |
| `make loadtest-smoke` | k6 single-iteration API smoke test |
| `make loadtest` | k6 sustained load test |
| `make validate` | Offline lint + render all three overlays |
| `make screenshots` | Re-capture `docs/images/*.png` (needs port-forwards) |
| `make down` | Uninstall CCF release |

## Examples

### Local full stack

```bash
make up && make obs && make pf-all
# UI http://localhost:8000  Grafana http://localhost:3000
```

### AKS smoke test

```bash
az aks get-credentials --resource-group <rg> --name <aks>
make aks ADMIN_PASSWORD='<strong-pw>'
make pf-aks
```

### Production

```bash
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='your-org'
make obs && make pf-aks
```

### Production with custom policies

```bash
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='your-org' \
  PLUGIN_VALUES="values/plugins/github.yaml values/plugins/custom-policies.yaml"
```

### Load test

```bash
make pf              # terminal 1
make loadtest-smoke  # terminal 2
make loadtest K6_VUS=20 K6_DURATION=5m
```

### Mirror private registry

```bash
make up REGISTRY_PREFIX=artifactory.example.com/docker-remote/compliance-framework
```
