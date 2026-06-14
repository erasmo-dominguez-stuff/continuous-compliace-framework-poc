# CCF API load tests (Grafana k6)

[k6](https://grafana.com/docs/k6/latest/) scripts to validate API performance after deploy.

## Prerequisites

1. CCF running (`make up` or `make aks`)
2. API reachable — either `make pf` in another terminal, or set `BASE_URL` to your ingress URL
3. [k6 installed](https://grafana.com/docs/k6/latest/set-up/install-k6/) (`brew install k6` on macOS)

## Commands

```bash
make pf              # terminal 1 — forwards API to localhost:8080
make loadtest-smoke  # terminal 2 — single-iteration smoke test
make loadtest        # terminal 2 — sustained load (default 10 VUs, 2 min)
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:8080` | CCF API base URL |
| `ADMIN_EMAIL` | `admin@ccf.local` | Admin user (local/aks overlay) |
| `ADMIN_PASSWORD` | `Admin12345!` | Admin password (local default) |
| `K6_VUS` | `10` | Virtual users during load phase |
| `K6_DURATION` | `2m` | Sustained load duration |
| `K6_RAMP` | `30s` | Ramp-up duration |
| `K6_SLEEP` | `1` | Sleep between iterations (seconds) |

## Production example

```bash
BASE_URL=https://api.ccf.example.com \
ADMIN_EMAIL=admin@your-org.example \
ADMIN_PASSWORD='...' \
K6_VUS=25 K6_DURATION=5m \
make loadtest
```
