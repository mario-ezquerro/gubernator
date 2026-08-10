# Gubernator SLO Specification (`SPEC-slo.md`)

Gubernator features a native **Service Level Objective (SLO)** engine and **Error Budget tracking** system powered by **Sloth** (`github.com/slok/sloth`). Inspired by Slok for Kubernetes, Gubernator adapts Kubernetes Custom Resources (`PrometheusSLO`, `OpenSLO`) into a lightweight, Docker Compose-native label specification, relational database tracking, and Prometheus rule generator.

---

## 🏛 1. SLO Definition Model (Compose Labels & REST API)

In Gubernator, SLOs are defined either via service labels in `docker-compose.yml` or programmatically via the REST API (`/v1/slo`).

### Compose Label Schema
| Label | Description | Example / Default |
| --- | --- | --- |
| `gbnt.slo.enable` | Enables SLO tracking for the service | `"true"` / `"false"` |
| `gbnt.slo.target` | Target availability objective percentage | `"99.9"` (99.9%) |
| `gbnt.slo.window` | Time window for error budget calculation | `"30d"`, `"7d"`, `"28d"` |
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

## 🎨 7. Web Dashboard Suite (`slo_page.dart`)

The Flutter Web Dashboard features a 5-tab SLO Management Suite:
1. **Overview & Error Budgets**: Live status cards, error budget remaining gauges, and burn rate badges.
2. **User Journeys**: High-level composite journey topology and bottleneck identification.
3. **Deployment Correlation Timeline**: Timeline graph correlating burn rate spikes with stack deployment events.
4. **SLI Templates & PromQL Generator**: Interactive PromQL builder with live metric preview.
5. **Backtest & Dry-Run Validator**: Form for pasting Compose YAML and running instant backtests against Prometheus.
