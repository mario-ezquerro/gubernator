# Service Level Objectives (SLOs) & Error Budget Engine

Gubernator features a native **Service Level Objective (SLO)** calculation and **Error Budget tracking** engine powered by **Sloth** ([github.com/slok/sloth](https://github.com/slok/sloth)) and inspired by **Pyrra** ([github.com/pyrra-dev/pyrra](https://github.com/pyrra-dev/pyrra)).

It adapts Kubernetes Custom Resources (`PrometheusSLO`, `OpenSLO`) into a lightweight, Docker Compose-native label specification, relational database tracking, Prometheus rule generator, and an integrated 5-tab Web Dashboard Suite.

---

## 🎯 Key Capabilities & Google SRE Standard

- **Google SRE Workbook Chapter 5 Multi-Burn-Rate Alerts**: Automatically generates standard multi-window multi-burn-rate Prometheus alerting rules:
  - 🚨 **Critical Page (1h)**: 2% budget consumed in 1 hour (14.4x burn rate over 5m & 1h windows).
  - 🚨 **Critical Page (6h)**: 5% budget consumed in 6 hours (6x burn rate over 30m & 6h windows).
  - ⚠️ **Warning Ticket (3d)**: 10% budget consumed in 3 days (3x burn rate over 2h & 3d windows).
  - ⚠️ **Warning Ticket (14d)**: 20% budget consumed in 14 days (1x burn rate over 6h & 14d windows).
- **Dynamic SLO Management**: Create, edit, or disable SLOs dynamically via Web UI modals or `POST /v1/slo/edit` / `DELETE /v1/slo/:service_id` REST API without editing Compose files.
- **Built-in SLI Templates**: Pre-configured query generators (`caddy-http`, `http-status`, `latency-p99`, `grpc`) eliminate the need to write raw PromQL manually.
- **Latency & Ratio Indicators**: Supports both event ratio SLOs and latency quantile thresholds (`gbnt.slo.indicator: "latency"`, `gbnt.slo.latency.threshold: "200ms"`).
- **Composite User Journeys**: Groups multi-service SLOs into end-to-end user journeys (`gbnt.slo.journey: "Checkout Flow"`), identifying the weakest-link bottleneck service.
- **Deployment Event Correlation**: Cross-references real-time SLO burn rate spikes with stack updates and task restarts.
- **SLO Backtesting & Dry-Run Validation**: Validates Compose YAML syntax and tests PromQL queries against historical Prometheus metrics prior to deployment.
- **RED Metrics Breakdown**: Real-time Request Rate (RPS), Error Rate (5xx/s), and P99 Latency (ms) alongside error budget gauges.
- **15s TTL In-Memory Query Caching**: High-performance backend caching keeps response times under 10ms.
- **Automated Grafana Dashboard Provisioning**: Automatically generates `/data/monitor/grafana/dashboards/slo_dashboard.json` on rule sync.
- **5-Tab Flutter Web Suite**: Rich interactive dashboard with real-time text search, multi-field sorting, clickable label chips, cards/table view toggles, `+ Configure / Add SLO` modal, and detail modals with historical trend charts.

---

## 📋 Docker Compose Label Schema

Add `gbnt.slo.*` labels to any service in `docker-compose.yml`:

| Label | Description | Example / Default |
| --- | --- | --- |
| `gbnt.slo.enable` | Enables SLO tracking for the service | `"true"` / `"false"` |
| `gbnt.slo.target` | Target availability objective percentage | `"99.9"` (99.9%) |
| `gbnt.slo.window` | Time window for error budget calculation | `"30d"`, `"7d"`, `"28d"` |
| `gbnt.slo.indicator` | Type of indicator | `"ratio"` (default) or `"latency"` |
| `gbnt.slo.latency.threshold` | Target latency threshold when indicator is `latency` | `"200ms"`, `"0.5s"` |
| `gbnt.slo.template` | Built-in SLI query template | `"caddy-http"`, `"http-status"`, `"latency-p99"`, `"grpc"` |
| `gbnt.slo.sli.error_query` | Custom PromQL error events rate query | `'sum(rate(caddy_http_response_status_code_total{status=~"5.."}[5m]))'` |
| `gbnt.slo.sli.total_query` | Custom PromQL total events rate query | `'sum(rate(caddy_http_response_status_code_total[5m]))'` |
| `gbnt.slo.journey` | Name of composite User Journey | `"Checkout Flow"`, `"User Authentication"` |

```yaml
version: "3.8"
services:
  payment-api:
    image: hashicorp/http-echo:latest
    labels:
      gbnt.slo.enable: "true"
      gbnt.slo.target: "99.9"
      gbnt.slo.window: "30d"
      gbnt.slo.template: "caddy-http"
      gbnt.slo.journey: "Checkout Flow"
```

---

## 💻 CLI Commands

```bash
# List active SLOs and real-time Error Budget % remaining
gbnt slo ls

# Manually trigger SLO rules generation and sync to Prometheus & Grafana
gbnt slo sync
```

---

## 🌐 REST API Endpoints

- `GET /v1/slo/ls`: Returns active SLO items with calculated error budget remaining and burn rate.
- `POST /v1/slo/edit`: Creates or updates an SLO configuration for any service dynamically.
- `DELETE /v1/slo/:service_id`: Removes/disables SLO configuration for a service.
- `POST /v1/slo/sync`: Triggers re-generation and synchronization of Prometheus & Grafana SLO rules.
- `GET /v1/slo/journeys`: Aggregates SLOs by composite User Journey and identifies bottleneck services.
- `GET /v1/slo/correlation`: Cross-references burn rate spikes with stack deployment events.
- `POST /v1/slo/validate`: Dry-run validation & PromQL metric backtesting for Compose YAML.
- `GET /v1/slo/history?service_id=...&range=24h`: Historical time-series trend points (`1h`, `6h`, `24h`, `7d`, `30d`).
- `GET /v1/slo/red?service_id=...`: Per-service RED metrics (Request Rate, Error RPS, P99 Latency).
