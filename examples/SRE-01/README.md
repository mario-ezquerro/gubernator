# SRE-01 — Full Site Reliability Engineering Stack

This is the **most advanced example**. It builds upon "The Empire" by deploying a complete SRE observability stack (Prometheus + Grafana + Loki) as a Gubernator-managed application, **scheduled and run by Gubernator itself**.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Docker Host                              │
│                                                                 │
│  ┌──── Control Plane (docker compose up) ───────────────────┐  │
│  │  Gubernator  :4000 :4001 :4002                           │  │
│  │  CoreDNS     :5353                                       │  │
│  │  Caddy       :80 :443                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                          │ gbnt stack deploy                    │
│                          ▼                                      │
│  ┌──── SRE Stack (managed by Gubernator) ────────────────────┐  │
│  │  Prometheus  :9090   ← scrapes Gubernator /metrics        │  │
│  │  Grafana     :3000   ← visualizes Prometheus data         │  │
│  │  Loki        :3100   ← aggregates logs                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- Docker and Docker Compose installed.
- `gbnt` binary compiled from the repository root:
  ```bash
  go build -o gbnt ./cmd/gbnt
  ```

---

## Step 1: Launch the Control Plane

Open a terminal **inside this directory** and start the Empire base:

```bash
cd examples/SRE-01
docker compose up -d
```

| Container | Ports | Description |
|-----------|-------|-------------|
| `gubernator-manager` | 4000 / 4001 / 4002 | Orchestrator + Web UI + Telemetry |
| `coredns` | 5353/udp | Internal DNS |
| `caddy` | 80 / 443 | Ingress |

Verify the control plane is healthy:
```bash
curl http://localhost:4002/health
# → {"status":"healthy"}
```

---

## Step 2: Access the Web UI

Open [http://localhost:4001](http://localhost:4001) in your browser.

- **Username**: `admin`
- **Password**: `admin`

You will see the Gubernator dashboard showing the active manager node and an empty task list.

---

## Step 3: Register a Local Worker

From the **repository root**, get the join token and register a local worker:

```bash
# Get the join token
TOKEN=$(curl -s -H "Authorization: Bearer admin" http://localhost:4000/v1/cluster/token | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "Token: $TOKEN"

# Join as worker
export GBNT_API_TOKEN=admin
./gbnt legion join --token $TOKEN --manager localhost:4000
```

Leave this terminal running.

---

## Step 4: Deploy the SRE Monitoring Stack

Open a new terminal at the **repository root** and deploy:

```bash
export GBNT_API_TOKEN=admin

./gbnt stack deploy -c examples/SRE-01/monitoring-stack.yml sre-monitoring
```

Gubernator will now:
1. Parse `monitoring-stack.yml` → create 3 services (Prometheus, Grafana, Loki).
2. Schedule a task per service to the active worker node.
3. Pull the images and start the containers.

---

## Step 5: Verify the SRE Stack

Wait ~30 seconds for images to pull, then verify:

```bash
# List running tasks
./gbnt task ls

# Check containers directly
docker ps | grep gbnt

# Check Prometheus is scraping Gubernator metrics
curl http://localhost:9090/api/v1/query?query=up
```

### Access the dashboards:

| Service | URL | Credentials |
|---------|-----|-------------|
| Gubernator Web UI | [http://localhost:4001](http://localhost:4001) | admin / admin |
| Prometheus | [http://localhost:9090](http://localhost:9090) | — |
| Grafana | [http://localhost:3000](http://localhost:3000) | admin / admin |
| Loki | [http://localhost:3100/ready](http://localhost:3100/ready) | — |
| Gubernator Metrics | [http://localhost:4002/metrics](http://localhost:4002/metrics) | — |
| Gubernator Swagger | [http://localhost:4002/swagger/index.html](http://localhost:4002/swagger/index.html) | — |

---

## Step 6: Configure Prometheus to Scrape Gubernator

Inside the container or by mounting a config, add this scrape job to Prometheus:

```yaml
scrape_configs:
  - job_name: 'gubernator'
    static_configs:
      - targets: ['host.docker.internal:4002']
```

> **Note**: `host.docker.internal` resolves to the Docker host from inside a container.

---

## Step 7: Edit and Redeploy from the Web UI

1. Open [http://localhost:4001](http://localhost:4001).
2. Find the `sre-monitoring` stack.
3. Click **Edit YAML** to modify the compose definition.
4. Click **Save & Redeploy** to apply changes without downtime.

---

## Step 8: Scale a Service

```bash
# Scale Grafana to 2 replicas
./gbnt service scale <service_id>=2
```

Or from the Web UI, edit the YAML and increase `replicas: 2` for `grafana`, then Redeploy.

---

## Step 9: Clean Up

```bash
export GBNT_API_TOKEN=admin

# Remove the SRE stack (stops and removes containers)
./gbnt stack rm <stack_id>

# Shut down the control plane
cd examples/SRE-01
docker compose down -v
```
