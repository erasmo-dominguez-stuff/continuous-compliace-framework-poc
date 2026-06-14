# Setup evidence

Visual proof that the standard CCF Helm package works end-to-end: control plane, agent registration, observability, and API load tests.

## Quick validation checklist

```bash
make check          # offline: helm lint + render local/aks/production
make up             # deploy CCF (Docker Desktop)
make obs            # Loki + Prometheus + Grafana + Alloy
make pf-all         # port-forward UI :8000, API :8080, Grafana :3000, …
make smoke          # wait for rollouts + helm test
make loadtest-smoke # k6 smoke (needs make pf in another terminal)
```

| Step | Expected result |
|------|-----------------|
| `kubectl -n ccf get pods` | `ccf-api`, `ccf-ui`, `ccf-postgres`, `ccf-agent` all Running |
| http://localhost:8000 | CCF login page (see below) |
| Admin → Agents | Agent `ccf-kubernetes-agent` registered |
| http://localhost:3000 | Grafana login (`admin` / `admin`) → dashboard **CCF - Logs & Metrics** |
| http://localhost:9091/targets | Prometheus scraping CCF API metrics |
| `make loadtest-smoke` | k6 passes login + agents + swagger checks |

## CCF UI

Login page after `make up && make pf`:

![CCF UI login](../images/ccf-ui-login.png)

**Admin → Agents** — agent auto-registered on install (`api.agentRegister` hook):

![CCF Admin Agents](../images/ccf-agents-admin.png)

Credentials (local / AKS smoke overlay): `admin@ccf.local` / `Admin12345!`

## CCF API (Swagger)

OpenAPI docs at http://localhost:8080/swagger/index.html:

![CCF API Swagger](../images/ccf-swagger.png)

## Observability

### Grafana

After `make obs`, open http://localhost:3000 (default `admin` / `admin`). The **CCF - Logs & Metrics** dashboard is pre-provisioned from `observability/grafana-values.yaml`.

![Grafana login](../images/grafana-login.png)

### Prometheus

Prometheus targets (Alloy scrapes API `:9090/metrics`; kube-state-metrics for pod health):

![Prometheus targets](../images/prometheus-targets.png)

Alert rules ship in `observability/prometheus-values.yaml` (`CCFAPINotReady`, `CCFAgentNotReady`, …).

## Load testing (k6)

Grafana [k6](https://grafana.com/docs/k6/latest/) scripts in [`loadtest/`](../loadtest/README.md):

```bash
make pf              # terminal 1
make loadtest-smoke  # terminal 2 — 1 iteration, public + authenticated endpoints
make loadtest        # sustained load (default 10 VUs, 2 min)
```

## Automated install hooks (charts)

Compared with [upstream CCF docs](https://compliance-framework.github.io/docs/), this Helm package automates:

| Hook / manifest | Purpose |
|-----------------|---------|
| `admin-bootstrap` Job | Creates default admin user (`api.adminUser`) |
| `agent-register` Job | Registers agent in UI + creates `ccf-agent-auth` Secret |
| `seed` Job | Imports demo OSCAL (`api.seedData`) for non-empty UI |
| `migrate` initContainer | Runs DB migrations before API starts |
| Prometheus pod annotations | `prometheus.io/scrape` on API when metrics enabled |
| Alloy values | Collects CCF pod logs + API metrics into Loki/Prometheus |
| Ingress + NetworkPolicy | Production overlay (`values/production.yaml`) |
| HPA + PDB | API/UI autoscaling and disruption budgets in prod |

No extra manifests are required for a standard demo. Production clusters should create Secrets documented in [`production.md`](./production.md) before `make prod`.

## Re-capture screenshots

Port-forward, then headless Chrome (macOS):

```bash
make pf-all   # or individual port-forwards
# docs/images/*.png are captured with Chrome --headless (see Makefile `screenshots` target)
make screenshots
```
