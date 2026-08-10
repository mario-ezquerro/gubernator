# Gubernator SLO Specification (`SPEC-slo.md`)

Gubernator features a native **Service Level Objective (SLO)** engine and **Error Budget tracking** system powered by **Sloth** (`github.com/slok/sloth`) and inspired by **Pyrra** (`github.com/pyrra-dev/pyrra`). It adapts Kubernetes Custom Resources (`PrometheusSLO`, `OpenSLO`) into a lightweight, Docker Compose-native label specification, relational database tracking, Prometheus rule generator, and an integrated 5-tab Web Dashboard Suite.

---

## 🏛 1. SLO Definition Model (Compose Labels & REST API)

In Gubernator, SLOs are defined either via service labels in `docker-compose.yml` or programmatically via the REST API (`/v1/slo`).

### Compose Label Schema
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

---

## ⚡ 2. Prometheus Recording & Alert Rules Generation

Gubernator automatically compiles all active service SLOs into a production-grade Prometheus rules file (`/data/monitor/prometheus/rules/slo_rules.yml`).

### Generated Recording Rules
- **SLI Error Ratio**: `slo:sli_error:ratio_rate5m`
- **Error Budget Remaining**: `slo:period_error_budget_remaining:ratio`
- **Current Burn Rate**: `slo:current_burn_rate:ratio`
- **Period Burn Rate**: `slo:period_burn_rate:ratio`

### Multi-Burn-Rate Alert Rules (Google SRE Standard)
- **Page Severity**: Fast burn rate consuming 2% error budget in 1 hour or 5% in 6 hours.
- **Ticket Severity**: Slow burn rate consuming 10% error budget in 3 days or 20% in 14 days.

---

## 📊 3. Built-in SLI Templates & PromQL Selectors

Gubernator provides built-in SLI query generators so users do not need to write raw PromQL manually.

1. **`caddy-http`**: Caddy reverse proxy status codes (`caddy_http_response_status_code_total`).
2. **`http-status`**: Generic HTTP container metrics (`http_requests_total`).
3. **`latency-p99`**: P99 response duration histogram (`http_request_duration_seconds_bucket`).
4. **`grpc`**: gRPC status codes (`grpc_server_handled_total`).

---

## 🧪 4. SLO Backtesting & Dry-Run Validation (`gbnt slo validate`)

Before deploying or redeploying a stack, Gubernator allows backtesting SLO definitions:
- **Syntax Validation**: Validates target percentage, window duration, and PromQL syntax.
- **PromQL Evaluation**: Evaluates `error_query` and `total_query` against Prometheus historical data.
- **Simulated Error Budget**: Calculates what the error budget remaining would have been over the past 24h / 7d.

---

## 🔗 5. SLO Composition (User Journeys)

Services can be grouped into higher-level **User Journeys** (e.g., `Checkout Flow` = `cart-service` + `payment-api` + `inventory-svc`).
- **Composite Objective**: Calculates the overall end-to-end journey availability.
- **Weakest Link Bottleneck**: Highlights the service currently causing the greatest degradation in the journey.

---

## 📈 6. Deployment Event Correlation

Gubernator cross-references real-time SLO error budget burn rate spikes with recent cluster actions:
- Stack deployment & redeployment timestamps (`db.Stack.UpdatedAt`).
- Task restart events (`db.Task`).
- Visualizes event correlation markers directly on the SLO trends timeline in the Web Dashboard.

---

## 🔍 7. Advanced Filtering, Search & Sorting

The SLO Dashboard includes rich interaction capabilities:
- **Real-Time Text Search**: Filter SLOs instantly by service name, stack name, or journey.
- **Clickable Label Filters**: Click on template or journey chips to isolate matching SLOs.
- **Multi-Field Sorting**: Sort by lowest error budget remaining, highest burn rate, or name.
- **Cards vs Data Table Toggle**: Switch between visual cards view and dense data table view.

---

## 📉 8. Time Series History & RED Metrics (Pyrra Integration)

- **Historical Trend Lines (`/v1/slo/history`)**: Fetches Prometheus range queries over configurable ranges (`1h`, `6h`, `24h`, `7d`, `30d`) to draw interactive error budget consumption and burn rate charts.
- **RED Metrics Breakdown**: Displays Request Rate (RPS), Error Rate (5xx/sec), and P99 Duration (ms) alongside each SLO detail modal.

---

## ⚡ 9. Backend In-Memory Query Caching

To ensure high performance and avoid hammering Prometheus, backend handlers cache Prometheus query results with a 15-second TTL.

---

## 📊 10. Automated Grafana Dashboard Provisioning

Whenever `slo.SyncSLORulesToPrometheus` runs, Gubernator automatically generates a comprehensive Grafana Dashboard JSON file at `/data/monitor/grafana/dashboards/slo_dashboard.json`, providing out-of-the-box Grafana panels for all active SLOs without manual JSON construction.

---

## 🛠 11. Dynamic SLO Management (Add, Edit, Disable via REST API & Web UI)

- **`POST /v1/slo/edit`**: Creates or updates an SLO definition for any deployed service in DB, updating service constraints and triggering `SyncSLORulesToPrometheus`.
- **`DELETE /v1/slo/:service_id`**: Removes SLO labels from a service, disabling tracking and resyncing Prometheus & Grafana rules.
- **Web UI Modal Form**: "+ Add / Configure SLO" button and "Edit / Configure SLO" action on cards and data table rows.

---

## 🎨 12. Web Dashboard Suite (`slo_page.dart`)

The Flutter Web Dashboard features a 5-tab SLO Management Suite:
1. **Overview & Error Budgets**: Live status cards, search/filter bar, sorting options, table/card toggle, "+ Configure SLO" button, error budget progress bars, and detail modal with RED metrics & historical charts.
2. **User Journeys**: High-level composite journey topology and bottleneck identification.
3. **Deployment Correlation Timeline**: Timeline graph correlating burn rate spikes with stack deployment events.
4. **SLI Templates & PromQL Generator**: Interactive PromQL builder with live metric preview.
5. **Backtest & Dry-Run Validator**: Form for pasting Compose YAML and running instant backtests against Prometheus.
