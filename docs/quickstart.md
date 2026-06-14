# Quick start workflows

Three values files, three commands. See [Setup evidence](./setup-evidence.md) for screenshots.

## Values files

| File | Command | Use case |
|------|---------|----------|
| `values/local.yaml` | `make up` | Docker Desktop demo |
| `values/aks.yaml` | `make aks` | AKS smoke test |
| `values/production.yaml` | `make prod` | Production (ingress, HA, GitHub plugin) |

## Prerequisites

- **Local:** Docker Desktop Kubernetes, `kubectl`, `helm`
- **AKS:** Azure CLI + cluster credentials
- **Load tests:** [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/) (`brew install k6`)
- **Policies:** [OPA CLI](https://www.openpolicyagent.org/) for `make policy`

---

## 1. Local demo

```bash
make up          # CCF + seed OSCAL + agent register + local-ssh plugin
make pf          # UI :8000, API :8080
```

Open http://localhost:8000 — `admin@ccf.local` / `Admin12345!`

Validate:

```bash
make smoke           # rollouts + helm test
make loadtest-smoke  # k6 (with make pf running)
```

Screenshots: [setup-evidence.md](./setup-evidence.md)

---

## 2. Observability

```bash
make up
make obs       # Loki + Prometheus + Grafana + Alloy
make pf-all    # UI, API, Grafana :3000, Prometheus :9091, Loki :3100
```

Grafana: http://localhost:3000 (`admin` / `admin`) → **CCF - Logs & Metrics**

---

## 3. AKS smoke test

Minimal validation that the stack works on Azure:

```bash
az aks get-credentials --resource-group <rg> --name <aks>
make aks ADMIN_PASSWORD='<strong-password>'
make pf-aks
```

Same login as local (`admin@ccf.local` + your password). Single replica, `managed-csi` persistence.

---

## 4. Production

```bash
# Create Secrets first — see docs/production.md
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='your-org'
make obs && make pf-aks
```

GitHub plugin config is built into `values/production.yaml`; token/org injected via Makefile.

---

## 5. Custom policies + GitHub

```bash
make policy
make policy-push POLICY_IMAGE=ghcr.io/my-org/ccf-custom-policies:v0.1.0 \
  GHCR_USER=$GHCR_USER GHCR_TOKEN=$GHCR_TOKEN
```

Edit `values/plugins/custom-policies.yaml` with your `POLICY_IMAGE`, then:

```bash
make prod ADMIN_PASSWORD='...' GITHUB_TOKEN='...' GITHUB_ORG='your-org' \
  PLUGIN_VALUES="values/plugins/github.yaml values/plugins/custom-policies.yaml"
```

See [values/plugins/README.md](../values/plugins/README.md) and [Plugins & policies](./policies-and-plugins.md).

---

## 6. Offline validation

```bash
make validate    # lint + render local, aks, production
make policy      # opa check + test
```

---

## Troubleshooting

| Problem | Action |
|---------|--------|
| `docker-desktop` not reachable | Docker Desktop → Enable Kubernetes |
| Can't login | `kubectl logs deploy/ccf-api -c migrate` |
| No agents in UI | Wait for `ccf-api-agent-register` hook; check `kubectl get secret ccf-agent-auth` |
| Empty UI | Seed enabled in local/aks; hard-refresh browser |
| `make up` timeout | Hooks need ~6 min first install; timeout is 8m |
| k6 fails | Run `make pf` first; check `LOADTEST_*` vars |

Full details: [Helm configuration — Troubleshooting](./helm-configuration.md#troubleshooting)
