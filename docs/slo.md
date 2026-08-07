# Service Level Objectives (SLOs) & Error Budget Engine

Gubernator features native **Service Level Objective (SLO)** calculation and **Error Budget tracking** powered by **Sloth** ([github.com/slok/sloth](https://github.com/slok/sloth)).

---

## 🎯 Key Capabilities

- **Google SRE Multi-Burn-Rate Alerts**: Automatically generates multi-window multi-burn-rate Prometheus alerting rules (1h 14.4x, 6h 6x, 1d 3x, 3d 1x).
- **Error Budget Calculation**: Calculates real-time remaining Error Budget % and current burn rates per service.
- **Docker Compose Native**: Enable SLO tracking by adding standard `gbnt.slo.*` labels to services in your `docker-compose.yml`.
- **Prometheus Auto-Sync**: Auto-writes Prometheus rules to `/data/monitor/prometheus/rules/slo_rules.yml`.

---

## 📋 Configuration in `docker-compose.yml`

Simply add `gbnt.slo.*` labels to any service:

```yaml
version: "3"
services:
  payment-api:
    image: payment-api:latest
    labels:
      gbnt.slo.enable: "true"
      gbnt.slo.target: "99.9"
      gbnt.slo.window: "30d"
      gbnt.slo.sli.error_query: 'sum(rate(http_requests_total{service="payment-api",status=~"5.."}[5m]))'
      gbnt.slo.sli.total_query: 'sum(rate(http_requests_total{service="payment-api"}[5m]))'
```

---

## 💻 CLI Commands

```bash
# List active SLOs and real-time Error Budget % remaining
gbnt slo ls

# Manually trigger SLO rules generation and sync to Prometheus
gbnt slo sync
```

---

## 🌐 REST API Endpoints

- `GET /v1/slo/ls`: Returns active SLO items with calculated error budget remaining and burn rate.
- `POST /v1/slo/sync`: Triggers re-generation and synchronization of Prometheus SLO rules.
