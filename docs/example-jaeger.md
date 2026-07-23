# Distributed Tracing (Jaeger Example)

This tutorial walks through deploying a 3-tier microservice architecture (`frontend`, `api-service`, `worker-service`) configured with **Caddy Ingress** domain `jaeger.gbnt.test` and integrated with Gubernator's built-in **Jaeger SRE Trace Collector**.

---

## 🏛 Overview & Architecture

When deploying microservice stacks, distributed tracing allows operators to follow a request as it travels through frontend gateways, backend APIs, and background processing workers.

```
Client / Browser ──► Caddy Ingress (jaeger.gbnt.test:80)
                           │
                           ▼
                    jaeger-frontend (:8080)
                           │  (creates parent span & OTLP trace)
                           ▼
                    jaeger-api (:8081)
                           │  (creates API child span & OTLP trace)
                           ▼
                    jaeger-worker (:8082)
                              (creates worker child span & OTLP trace)
```

All 3 microservices transmit OpenTelemetry trace spans directly to **`gbnt-monitor-jaeger`** over OTLP HTTP (`:4318/v1/traces`). Traces can be inspected inside the Gubernator Web UI under the **Jaeger Traces** tab or directly at `http://localhost:16686`.

---

## 📜 Compose File Breakdown

The stack definition is located at [`examples/example-jaeger/docker-compose.yml`](https://github.com/mario-ezquerro/gubernator/tree/main/examples/example-jaeger/docker-compose.yml):

```yaml
version: '3.8'

services:
  frontend:
    image: python:3.11-alpine
    container_name: jaeger-frontend
    ports:
      - "8080:8080"
    deploy:
      replicas: 1
      placement:
        constraints:
          - stack.name == jaeger-stack
          - ingress.host == jaeger.gbnt.test

  api-service:
    image: python:3.11-alpine
    container_name: jaeger-api-service
    ports:
      - "8081:8081"

  worker-service:
    image: python:3.11-alpine
    container_name: jaeger-worker-service
    ports:
      - "8082:8082"
```

---

## 🚀 Deployment

### Step 1: Start the SRE Monitoring Stack

Ensure the Jaeger collector and SRE stack are running on the Manager node:

```bash
./gbnt monitor init
```

### Step 2: Deploy the Jaeger Example Stack

```bash
./gbnt stack deploy -c examples/example-jaeger/docker-compose.yml jaeger-stack
```

### Step 3: Verify Stack Containers

```bash
./gbnt task ls
```

You will see:
- `jaeger-frontend` running on port `8080` (with Caddy routing `jaeger.gbnt.test`)
- `jaeger-api-service` running on port `8081`
- `jaeger-worker-service` running on port `8082`

---

## 🧪 Testing Traces

### Generate HTTP Requests

Send a request to the Caddy ingress endpoint:

```bash
curl -H "Host: jaeger.gbnt.test" http://localhost:80/
```

Response snippet:
```html
<h1>🚀 Jaeger Tracing Example (jaeger.gbnt.test)</h1>
<p style="color: #38bdf8;">Generated Trace ID: 4bf92f3577b34da6a3ce929d0e0e4736</p>
```

---

## 📈 Visualizing in Jaeger UI

1. Open **[http://localhost:4001](http://localhost:4001)** in your browser.
2. Click on the **Jaeger Traces** tab (5th tab) or click the 📈 timeline icon in the top app bar.
3. Select **`jaeger-frontend`** in the Service selector and click **Find Traces**.
4. Click on any trace item to expand the waterfall view showing latency for `jaeger-frontend` -> `jaeger-api` -> `jaeger-worker`.
