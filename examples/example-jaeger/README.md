# Example Jaeger — Distributed Tracing Stack

This example demonstrates **distributed tracing** across three microservices (`jaeger-frontend`, `jaeger-api`, and `jaeger-worker`) sending OpenTelemetry telemetry traces over OTLP (`:4318/v1/traces`) to the Gubernator SRE Jaeger collector (`gbnt-monitor-jaeger`).

The frontend service is exposed externally via Caddy Ingress using the domain **`jaeger.gbnt.test`**.

---

## 🏗 Stack Architecture

```
                                 ┌───────────────────────────┐
                                 │   Caddy Ingress (:80)     │
                                 └─────────────┬─────────────┘
                                               │ jaeger.gbnt.test
                                               ▼
                                 ┌───────────────────────────┐
                                 │      jaeger-frontend      │  ─── OTLP ──┐
                                 │        (Port :8080)       │             │
                                 └─────────────┬─────────────┘             │
                                               │ HTTP                      │
                                               ▼                           │
                                 ┌───────────────────────────┐             │
                                 │        jaeger-api         │  ─── OTLP ──┼──►  Jaeger Collector
                                 │        (Port :8081)       │             │     (gbnt-monitor-jaeger:4318)
                                 └─────────────┬─────────────┘             │     UI: http://localhost:4001/jaeger/
                                               │ HTTP                      │
                                               ▼                           │
                                 ┌───────────────────────────┐             │
                                 │       jaeger-worker       │  ─── OTLP ──┘
                                 │        (Port :8082)       │
                                 └───────────────────────────┘
```

---

## 🚀 Quickstart Deployment

Deploy the stack with a single command using the Gubernator CLI:

```bash
./gbnt stack deploy -c examples/example-jaeger/docker-compose.yml jaeger-stack
```

Or via the **Gubernator Web UI Dashboard** (`http://localhost:4001`):
1. Click **+ Add Stack**
2. Paste the contents of `examples/example-jaeger/docker-compose.yml`
3. Click **Deploy Stack**

---

## 🧪 Testing the Microservices & Ingress

1. **Test Ingress via Domain**:
   ```bash
   curl -H "Host: jaeger.gbnt.test" http://localhost:80/
   ```

2. **Test Direct Frontend Port**:
   ```bash
   curl http://localhost:8080/
   ```

---

## 🔍 Visualizing Traces in Jaeger UI

1. Open the **Gubernator Web UI Dashboard** at **[http://localhost:4001](http://localhost:4001)**.
2. Select the **Jaeger Traces** tab (or click the 📈 Timeline icon in the top app bar).
3. Select **`jaeger-frontend`**, **`jaeger-api`**, or **`jaeger-worker`** from the **Service** dropdown.
4. Click **Find Traces** to view trace timelines, parent-child span relationships, and latency breakdowns.
