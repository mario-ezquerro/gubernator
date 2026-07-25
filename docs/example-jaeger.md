# Distributed Tracing (Jaeger Example)

This tutorial walks through deploying a microservice architecture configured with **Caddy Ingress** domain `jaeger.gbnt.test`, generating synthetic OpenTelemetry traffic, and integrating with Gubernator's built-in **Jaeger SRE Trace Collector**.

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
                    jaeger-api (:8085)
                           │  (creates API child span & OTLP trace)
                           ▼
                    jaeger-worker (:8086)
                              (creates worker child span & OTLP trace)
```

All microservices transmit OpenTelemetry trace spans directly to **`gbnt-monitor-jaeger`** over OTLP HTTP (`:4318/v1/traces`). Traces can be inspected inside the Gubernator Web UI under the **Jaeger Traces** tab or directly at `http://localhost:16686`.

---

## 📜 Tracing Scenarios

1. **Landing Page (`GET /`)**: Standard web page visit emitting a 3-span cascade (`jaeger-frontend` ➔ `jaeger-api` ➔ `jaeger-worker`).
2. **E-Commerce Checkout (`GET /checkout`)**: 4-span transaction (`checkout-frontend` ➔ `payment-gateway` ➔ `inventory-service` ➔ `notification-worker`).
3. **User Authentication (`GET /auth/login`)**: 3-span login flow (`auth-frontend` ➔ `identity-provider` ➔ `user-db`).
4. **Catalog Search (`GET /search?q=query`)**: 3-span search query with cache hit/miss semantics (`search-frontend` ➔ `redis-cache` ➔ `elasticsearch-cluster`).
5. **Simulated Error (`GET /error-demo`)**: 3-span trace demonstrating error reporting, HTTP 500 status codes, and exception attributes.

---

## 🚀 Deployment Steps

Deploy the stack via `gbnt`:

```bash
gbnt stack deploy -f examples/example-jaeger/docker-compose.yml jaeger-stack
```

Verify service status:

```bash
gbnt service ls
```

---

## 🚦 Traffic Generation Tools (`generate_traces.py` & `send_traces.sh`)

Gubernator provides automated scripts to populate Jaeger with rich, multi-service OpenTelemetry traces:

### 1. Python Traffic Generator (`generate_traces.py`)

Sends customizable trace batches directly via OTLP (`:4318`) or HTTP requests (`:8080`):

```bash
# Send 20 traces cycling through all scenarios directly to Jaeger OTLP:
python3 examples/example-jaeger/generate_traces.py --count 20 --scenario all --target otlp

# Send 10 Checkout flow traces to a remote manager VM:
python3 examples/example-jaeger/generate_traces.py --count 10 --scenario checkout --endpoint http://192.168.252.18:4318/v1/traces

# Generate 15 HTTP requests against the frontend server:
python3 examples/example-jaeger/generate_traces.py --count 15 --scenario all --target http --endpoint http://localhost:8080/
```

#### CLI Parameters

| Flag | Description | Default |
| --- | --- | --- |
| `--count N` | Number of trace batches to send | `10` |
| `--scenario` | Scenario preset (`all`, `checkout`, `auth`, `search`, `error`, `landing`) | `all` |
| `--target` | Target protocol (`otlp` or `http`) | `otlp` |
| `--endpoint URL` | Target endpoint URL | `http://localhost:4318/v1/traces` |
| `--delay SECONDS` | Inter-request delay in seconds | `0.2` |

### 2. POSIX Shell Generator (`send_traces.sh`)

Lightweight shell script powered by `curl`:

```bash
# Send 10 traces to local Jaeger OTLP:
./examples/example-jaeger/send_traces.sh 10

# Send 25 traces to remote manager node:
./examples/example-jaeger/send_traces.sh 25 http://192.168.252.18:4318/v1/traces
```

---

## 🔍 Inspecting Traces in Jaeger UI

1. Open Gubernator Web UI at `http://localhost:4001/` and navigate to the **Jaeger** tab.
2. Select a service from the **Service** dropdown (e.g., `checkout-frontend`, `auth-frontend`, or `jaeger-frontend`).
3. Click **Find Traces**.
4. Click on any trace to inspect:
   - Total latency and span breakdown.
   - Parent-child span hierarchy.
   - Resource and span attributes (e.g. `db.system=postgresql`, `payment.provider=stripe`, `user.id=usr_4821`).
   - Failed spans highlighted in red with error logs and stack traces.
