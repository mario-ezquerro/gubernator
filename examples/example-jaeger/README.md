# Gubernator Example — Distributed Tracing Stack (Jaeger)

This example demonstrates **Distributed Tracing** in Gubernator using **OpenTelemetry OTLP** (`:4318`) and **Jaeger UI** (`:16686` or integrated into Gubernator Web UI at `/jaeger/`).

---

## 🏗 Architecture Overview

```
                        ┌──────────────────────────────┐
                        │   Gubernator Manager / UI    │
                        │   (http://localhost:4001)    │
                        └──────────────┬───────────────┘
                                       │
                        ┌──────────────▼───────────────┐
                        │     Jaeger UI (Port 16686)   │
                        └──────────────▲───────────────┘
                                       │ (Query Traces)
                        ┌──────────────┴───────────────┐
                        │  Gubernator Monitor Stack    │
                        │   (gbnt-monitor-jaeger)      │
                        │   OTLP HTTP Receiver :4318   │
                        └──────────────▲───────────────┘
                                       │ OTLP Traces (Protobuf-JSON)
           ┌───────────────────────────┼───────────────────────────┐
           │                           │                           │
┌──────────┴───────────┐    ┌──────────┴───────────┐    ┌──────────┴───────────┐
│   jaeger-frontend    │    │    jaeger-api        │    │    jaeger-worker     │
│   (Port 8080)        │───►│    (Port 8085)       │───►│    (Port 8086)       │
│ ingress:             │    │                      │    │                      │
│ jaeger.gbnt.test     │    │                      │    │                      │
└──────────────────────┘    └──────────────────────┘    └──────────────────────┘
```

---

## ⚡ Microservices & Scenarios Included

1. **`jaeger-frontend`** (`:8080`): Web frontend receiving requests on `http://jaeger.gbnt.test/`. Generates root trace spans and routes internal logic to backend services.
2. **`jaeger-api`** (`:8085`): Internal REST API microservice processing requests and emitting child spans.
3. **`jaeger-worker`** (`:8086`): Background worker microservice handling asynchronous jobs and emitting grandchild spans.

### Supported Tracing Scenarios

- **Landing Page (`GET /`)**: 3-span trace (`jaeger-frontend` ➔ `jaeger-api` ➔ `jaeger-worker`).
- **E-Commerce Checkout (`GET /checkout`)**: 4-span trace (`checkout-frontend` ➔ `payment-gateway` ➔ `inventory-service` ➔ `notification-worker`).
- **User Authentication (`GET /auth/login`)**: 3-span trace (`auth-frontend` ➔ `identity-provider` ➔ `user-db`).
- **Catalog Search (`GET /search?q=query`)**: 3-span trace with cache hit/miss semantics (`search-frontend` ➔ `redis-cache` ➔ `elasticsearch-cluster`).
- **Simulated Error (`GET /error-demo`)**: 3-span trace with HTTP 500 error code, exception messages, and failed span flags.

---

## 🚀 Quickstart & Deployment

Deploy the stack to Gubernator via CLI:

```bash
gbnt stack deploy -f examples/example-jaeger/docker-compose.yml jaeger-stack
```

Or via REST API:

```bash
curl -X POST http://localhost:4000/v1/stack/deploy \
  -H "Authorization: Bearer $GBNT_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "jaeger-stack",
    "compose_raw": "'$(cat examples/example-jaeger/docker-compose.yml | sed 's/"/\\"/g' | tr '\n' '\r' | sed 's/\r/\\n/g')'"
  }'
```

---

## 🚦 Traffic Generation Tools (`generate_traces.py` & `send_traces.sh`)

To simulate real-world OpenTelemetry trace streams and populate Jaeger with realistic data, use the included traffic generator scripts:

### 1. Python Traffic Generator (`generate_traces.py`)

Sends custom trace scenarios directly to Jaeger OTLP (`:4318`) or generates HTTP requests against the frontend (`:8080`):

```bash
# Send 15 traces cycling through all scenarios directly to Jaeger OTLP:
python3 examples/example-jaeger/generate_traces.py --count 15 --scenario all --target otlp

# Send 10 Checkout flow traces to a remote manager VM:
python3 examples/example-jaeger/generate_traces.py --count 10 --scenario checkout --endpoint http://192.168.252.18:4318/v1/traces

# Generate 20 HTTP requests against the frontend server:
python3 examples/example-jaeger/generate_traces.py --count 20 --scenario all --target http --endpoint http://localhost:8080/
```

#### CLI Options

| Flag | Description | Default |
| --- | --- | --- |
| `--count N` | Number of trace batches to send | `10` |
| `--scenario` | Scenario preset (`all`, `checkout`, `auth`, `search`, `error`, `landing`) | `all` |
| `--target` | Target protocol (`otlp` or `http`) | `otlp` |
| `--endpoint URL` | Custom endpoint URL | `http://localhost:4318/v1/traces` |
| `--delay SECONDS` | Inter-request delay in seconds | `0.2` |

### 2. POSIX Shell Generator (`send_traces.sh`)

Lightweight alternative powered by `curl` for environments without Python:

```bash
# Send 10 traces to local Jaeger OTLP:
./examples/example-jaeger/send_traces.sh 10

# Send 25 traces to remote manager node:
./examples/example-jaeger/send_traces.sh 25 http://192.168.252.18:4318/v1/traces
```

---

## 🔍 Trace Inspection in Jaeger UI

1. Open Gubernator Web Dashboard at `http://localhost:4001/` and select the **Jaeger** tab (or open `http://localhost:16686/` directly).
2. Select a service (e.g. `checkout-frontend`, `auth-frontend`, or `jaeger-frontend`) in the **Service** dropdown.
3. Click **Find Traces**.
4. Click on any trace to inspect span breakdown, latencies, tags (`db.system`, `payment.provider`, `http.method`), and exception stack traces.
