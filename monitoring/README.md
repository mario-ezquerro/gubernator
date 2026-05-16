# Gubernator Monitoring Stack

Pre-configured **Prometheus + Grafana** stack that automatically:
- Scrapes Gubernator's metrics from `:4002/metrics`
- Loads a pre-built Gubernator dashboard in Grafana

## Quick Start

```bash
# 1. Make sure Gubernator image is built
cd ..
docker build -t gubernator:latest .

# 2. Start the full monitoring stack
cd monitoring/
docker compose up -d
```

## Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Gubernator Web UI | http://localhost:4001 | admin / admin |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |
| Gubernator Metrics | http://localhost:4002/metrics | — |
| Gubernator Health | http://localhost:4002/health | — |
| Gubernator Swagger | http://localhost:4002/swagger/index.html | — |

The **Gubernator — Cluster Overview** dashboard loads automatically in Grafana.

## Tear Down

```bash
docker compose down -v   # -v removes data volumes too
```
