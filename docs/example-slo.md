# Service Level Objectives (SLO) & Error Budget Example

This guide demonstrates how to deploy a sample application with **Service Level Objectives (SLO)** and **Error Budget tracking** using Gubernator's native Slok & Pyrra engine.

---

## ⚙️ Prerequisites

Before deploying an SLO stack, ensure Gubernator's **SRE Observability Stack** (Prometheus & cAdvisor) is initialized on the Manager node:

```bash
gbnt monitor init
```

---

## 📋 Docker Compose Definition

To enable SLO tracking for a service, specify `gbnt.slo.*` labels in `docker-compose.yml`:

```yaml
version: "3.8"

services:
  payment-api:
    image: hashicorp/http-echo:latest
    command: ["-text=Payment API OK", "-listen=:8080"]
    ports:
      - "8080:8080"
    labels:
      gbnt.slo.enable: "true"
      gbnt.slo.target: "99.9"
      gbnt.slo.window: "30d"
      gbnt.slo.template: "caddy-http"
      gbnt.slo.journey: "Checkout Flow"
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.gbnt.node.role == worker
          - ingress.host == payment.gbnt.local
```

---

## 🚀 Deployment Steps

1. **Deploy Stack:**
   ```bash
   gbnt stack deploy -c examples/example-slo/docker-compose.yml slo-demo
   ```

2. **Check Active SLOs & Error Budgets:**
   ```bash
   gbnt slo ls
   ```

3. **Explore Web Dashboard Suite (`http://localhost:4001`):**
   - **Overview & Budgets**: Search, sort, and toggle between Cards and Data Table views.
   - **User Journeys**: Inspect composite journey health and bottleneck identification.
   - **Deployment Correlation**: View stack update events correlated with burn rate spikes.
   - **SLI Templates**: Browse built-in PromQL templates (`caddy-http`, `http-status`, `latency-p99`, `grpc`).
   - **Backtest & Validator**: Paste Compose YAML to run instant dry-run backtests.

4. **Simulate Errors & Burn Error Budget:**
   Run the traffic generator to send HTTP errors and watch your Error Budget burn down live:
   ```bash
   ./examples/example-slo/generate_errors.sh <MANAGER-IP>
   ```

---

## 📊 Automated Grafana Dashboard

Gubernator automatically generates a complete Grafana Dashboard for all active SLOs at `/data/monitor/grafana/dashboards/slo_dashboard.json`, accessible directly via **[http://localhost:3000](http://localhost:3000)** or via the embedded Grafana tab in the Web Dashboard.
