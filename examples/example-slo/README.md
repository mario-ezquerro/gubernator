# 🎯 Example: SLO & Error Budget Tracking (`example-slo`)

This example demonstrates how to configure, deploy, and monitor **Service Level Objectives (SLOs)** and **Error Budgets** in Gubernator using native **Sloth** ([github.com/slok/sloth](https://github.com/slok/sloth)) integration.

---

## 📋 Stack Architecture (`docker-compose.yml`)

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
      gbnt.slo.sli.error_query: 'sum(rate(http_requests_total{service="payment-api",status=~"5.."}[5m]))'
      gbnt.slo.sli.total_query: 'sum(rate(http_requests_total{service="payment-api"}[5m]))'
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.gbnt.node.role == worker
```

---

## 🚀 How to Deploy & Verify

### 1. Deploy the Stack
```bash
gbnt stack deploy -c examples/example-slo/docker-compose.yml slo-demo
```

### 2. Inspect Active SLOs & Error Budget
Run `gbnt slo ls` to view the service SLO target (99.9%), 30-day time window, remaining error budget %, and current burn rate:

```bash
gbnt slo ls
```

*Output:*
```text
SERVICE              STACK           TARGET     WINDOW     ERROR BUDGET REMAINING BURN RATE    STATUS
----------------------------------------------------------------------------------------------------
payment-api          slo-demo        99.9%      30d        100.00%              0.00x        HEALTHY 🟢
```

### 3. Force Sync Prometheus Rules
```bash
gbnt slo sync
```

This auto-generates multi-window multi-burn-rate Prometheus recording and alerting rules in `/data/monitor/prometheus/rules/slo_rules.yml`.

### 4. View in Prometheus / Grafana
Open Prometheus on `http://<manager-ip>:9090/rules` to view the generated Sloth rules:
- `slo:objective:ratio`
- `slo:error_budget:ratio`
- `slo:period_error_budget_remaining:ratio`
- `slo:current_burn_rate:ratio`
- Multi-burn-rate page & ticket alert rules.
