# Makefile reference

The `Makefile` automates local (Docker Desktop) and AKS deployments. Run `make help` for the public target list.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KUBE_CONTEXT` | `docker-desktop` | Context for local `helm`/`kubectl` |
| `NAMESPACE` | `ccf` | CCF release namespace |
| `OBS_NAMESPACE` | `observability` | Observability stack namespace |
| `RELEASE` | `ccf` | Helm release name |
| `CHART_DIR` | `.` | Umbrella chart path |
| `ENV_LOCAL` | `values/local.yaml` | Local environment overlay |
| `ENV_AKS` | `values/aks.yaml` | AKS environment overlay |
| `PLUGIN_VALUES` | `values/plugins/local-ssh.yaml` | Space-separated plugin overlays |
| `EXTRA_VALUES` | (empty) | Extra overlays, e.g. `values/postgres-ha.yaml` |
| `GITHUB_TOKEN` | (empty) | Injected to GitHub plugin config (not stored in git) |
| `GITHUB_ORG` | (empty) | GitHub organisation for plugin |
| `PG_PASSWORD` | (empty) | Bitnami + API DB password (HA overlay) |
| `ADMIN_PASSWORD` | (empty) | Enables admin bootstrap + sets password |
| `SEED` | (empty) | Set to `1` to enable OSCAL demo seed |
| `POLICY_DIR` | `policies` | Rego source directory |
| `POLICY_BUNDLE` | `dist/policies-bundle.tar.gz` | Built bundle output |
| `POLICY_IMAGE` | `ghcr.io/your-org/ccf-custom-policies:v0.1.0` | OCI push destination |
| `GHCR_USER` / `GHCR_TOKEN` | (empty) | Registry credentials for `policy-push` |

### How overlays combine

`make up` runs:

```text
helm upgrade --install ccf . \
  -f values/local.yaml \
  $(PLUGIN_ARGS) $(EXTRA_ARGS) $(SECRET_ARGS) $(SEED_ARGS)
```

`make aks` uses `values/aks.yaml` instead and the **current** kube-context (no `KUBE_CONTEXT` pin).

---

## Public targets

### CCF stack

| Target | Description |
|--------|-------------|
| `make up` | Install/upgrade full CCF on Docker Desktop |
| `make down` | Uninstall CCF release (cluster stays) |
| `make status` | `kubectl get pods,svc -n ccf` |
| `make pf` | Port-forward UI (:8000) + API (:8080) |
| `make pf-all` | Port-forward UI, API, Grafana, Prometheus, Loki |

### Observability

| Target | Description |
|--------|-------------|
| `make obs` | Install Loki + Prometheus + Grafana + Alloy |
| `make obs-grafana` | Port-forward Grafana only (:3000) |
| `make obs-loki` | Port-forward Loki only (:3100) |

### AKS

| Target | Description |
|--------|-------------|
| `make aks` | Install CCF on current kube-context |
| `make pf-aks` | Port-forward UI/API on current context |
| `make install-aks` | Alias for `make aks` |

### Policies

| Target | Description |
|--------|-------------|
| `make policy` | `opa check` + `opa test` on `policies/` |
| `make policy-push` | Build bundle + push to `POLICY_IMAGE` |

### Validation

| Target | Description |
|--------|-------------|
| `make validate` | Offline: lint + render all env/plugin combos |
| `make smoke` | Live: wait for rollouts + `helm test` |
| `make test` | Run helm test hooks only |

---

## Internal targets (not in `make help`)

| Target | Purpose |
|--------|---------|
| `deps` | `helm dependency build` |
| `lint` | `helm lint` umbrella + subcharts |
| `template-all` | Render every overlay combination |
| `docker-ensure` | Verify Docker Desktop K8s reachable |
| `obs-repos` | Add Grafana/Prometheus helm repos |
| `obs-stack` | Loki + Prometheus + Grafana only |
| `obs-alloy` | Alloy collector only |
| `policy-validate` | `opa check` |
| `policy-test` | `opa test -v` |
| `policy-build` | `opa build` → `dist/` |
| `install-app` / `install-agent` | Standalone subchart install |
| `_pf` | Internal port-forward helper |

---

## Examples

### Local with everything

```bash
make up SEED=1 \
  PLUGIN_VALUES="values/plugins/github.yaml" \
  GITHUB_TOKEN=$GITHUB_TOKEN GITHUB_ORG=my-org

make obs
make pf-all
```

### AKS with HA database

```bash
az aks get-credentials -g myrg -n myaks

make aks \
  EXTRA_VALUES="values/postgres-ha.yaml" \
  PG_PASSWORD='...' \
  ADMIN_PASSWORD='...' \
  SEED=1
```

### Policy development loop

```bash
# edit policies/*.rego
make policy
make policy-push POLICY_IMAGE=ghcr.io/me/policies:v0.2.0 GHCR_USER=me GHCR_TOKEN=$TOKEN
make up PLUGIN_VALUES="values/plugins/github.yaml values/plugins/custom-policies.yaml" ...
```

### Offline CI check

```bash
make validate && make policy
```

---

## Port-forward map (`make pf-all`)

| Local port | Service | Namespace |
|------------|---------|-----------|
| 8000 | `ccf-ui` | `ccf` |
| 8080 | `ccf-api` | `ccf` |
| 3000 | `ccf-grafana` | `observability` |
| 9091 | `prometheus-server` | `observability` |
| 3100 | `loki` | `observability` |

Observability forwards are skipped silently if those releases are not installed.
