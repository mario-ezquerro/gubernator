# Service Level Objectives (SLO) & Error Budget Example

This guide demonstrates how to deploy a sample application with **Service Level Objectives (SLO)** and **Error Budget tracking** using Gubernator's native **Sloth** engine.

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
      gbnt.slo.sli.error_query: 'sum(rate(caddy_http_response_status_code_total{status=~"5.."}[5m]))'
      gbnt.slo.sli.total_query: 'sum(rate(caddy_http_response_status_code_total[5m]))'
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

3. **Simulate Errors & Burn Error Budget:**
   Run the traffic generator to send HTTP errors and watch your Error Budget burn down live:
   ```bash
   ./examples/example-slo/generate_errors.sh <MANAGER-IP>
   ```

---

## 📊 Error Budget Metrics in Prometheus

Gubernator automatically generates standard Sloth recording metrics in Prometheus:

- `slo:objective:ratio`: Target objective (e.g. `0.999`).
- `slo:error_budget:ratio`: Target error budget (e.g. `0.001`).
- `slo:period_error_budget_remaining:ratio`: Remaining error budget percentage.
- `slo:current_burn_rate:ratio`: Short-term error budget burn rate multiplier.
- `slo:period_burn_rate:ratio`: Long-term error budget burn rate multiplier.
