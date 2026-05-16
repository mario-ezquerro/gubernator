# Observability — Healthcheck, Metrics & Monitoring

Gubernator exposes all observability endpoints on **port 4002**, which is public (no authentication required) to allow easy scraping by Prometheus and other monitoring tools.

!!! tip "Port 4002 is intentionally public"
    This port is designed for internal infrastructure monitoring. In production, firewall it from the public internet and only expose it to your Prometheus / monitoring network.

---

## Endpoints Summary

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | JSON health check — use for load balancers and readiness probes |
| `/metrics` | GET | Prometheus-format metrics (Gubernator + Go runtime) |
| `/swagger/index.html` | GET | Interactive Swagger UI for the REST API |

---

## Health Check

### HTTP Endpoint

```bash
curl http://localhost:4002/health
```

**Response when healthy:**
```json
{"status": "healthy"}
```

The endpoint always returns `200 OK` as long as the Gubernator process is running. It can be used as:

=== "Docker HEALTHCHECK"

    ```dockerfile
    HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
      CMD curl -f http://localhost:4002/health || exit 1
    ```
    This is already built into the official `Dockerfile`.

=== "Docker Compose"

    ```yaml
    services:
      gubernator:
        image: gubernator:latest
        healthcheck:
          test: ["CMD", "curl", "-f", "http://localhost:4002/health"]
          interval: 30s
          timeout: 5s
          retries: 3
          start_period: 10s
    ```

=== "Kubernetes Probe"

    ```yaml
    livenessProbe:
      httpGet:
        path: /health
        port: 4002
      initialDelaySeconds: 10
      periodSeconds: 30
      timeoutSeconds: 5
      failureThreshold: 3

    readinessProbe:
      httpGet:
        path: /health
        port: 4002
      initialDelaySeconds: 5
      periodSeconds: 10
    ```

=== "CLI / Script"

    ```bash
    # Wait until Gubernator is healthy before running commands
    until curl -sf http://localhost:4002/health; do
      echo "Waiting for Gubernator..."
      sleep 2
    done
    echo "Gubernator is healthy!"
    ```

---

## Prometheus Metrics

### Available Metrics

#### Gubernator Custom Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `gbnt_total_nodes` | Gauge | Number of nodes currently registered in the cluster |
| `gbnt_total_tasks` | Gauge | Number of tasks (containers) scheduled in the cluster |

These update every **15 seconds** via the internal `startWatchtowers()` loop.

#### Go Runtime Metrics (automatic)

| Metric | Description |
|--------|-------------|
| `go_goroutines` | Number of running goroutines |
| `go_memstats_alloc_bytes` | Heap memory in use |
| `go_memstats_sys_bytes` | Total memory obtained from OS |
| `go_gc_duration_seconds` | GC pause durations (p50, p75, p99) |
| `go_info` | Go version information |
| `process_cpu_seconds_total` | CPU time consumed |
| `process_open_fds` | Number of open file descriptors |

### Scraping Manually

```bash
# Raw Prometheus text format
curl http://localhost:4002/metrics

# Filter only Gubernator metrics
curl -s http://localhost:4002/metrics | grep "^gbnt_"
```

**Example output:**
```
# HELP gbnt_total_nodes Current number of nodes registered in the cluster.
# TYPE gbnt_total_nodes gauge
gbnt_total_nodes 2
# HELP gbnt_total_tasks Current number of tasks scheduled in the cluster.
# TYPE gbnt_total_tasks gauge
gbnt_total_tasks 5
```

---

## Prometheus Configuration

### Minimal scrape config

Add this to your existing `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'gubernator'
    scrape_interval: 15s
    metrics_path: '/metrics'
    static_configs:
      - targets: ['<gubernator-host>:4002']
        labels:
          service: 'gubernator'
```

Replace `<gubernator-host>` with:
- `localhost` — if Prometheus runs on the same machine
- `gubernator` — if running in the same Docker Compose network
- `host.docker.internal` — if Prometheus is in Docker and Gubernator is on the host (Mac/Windows)

---

## Monitoring Stack (Prometheus + Grafana)

The repository includes a ready-to-use `monitoring/` directory with:

```
monitoring/
├── docker-compose.yml                          # Gubernator + Prometheus + Grafana
├── prometheus/
│   └── prometheus.yml                          # Pre-configured scrape job
└── grafana/
    ├── provisioning/
    │   ├── datasources/prometheus.yml          # Auto-connects Prometheus
    │   └── dashboards/dashboards.yml           # Auto-loads dashboards
    └── dashboards/
        └── gubernator.json                     # Pre-built Gubernator dashboard
```

### Start the Full Stack

```bash
# Build Gubernator image first (if not using Docker Hub)
docker build -t gubernator:latest .

# Launch everything
cd monitoring/
docker compose up -d
```

### Verify

```bash
# Check all containers are healthy
docker compose ps

# Check Gubernator is being scraped
curl 'http://localhost:9090/api/v1/query?query=up{job="gubernator"}' | python3 -m json.tool
```

### Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Gubernator Web UI | [http://localhost:4001](http://localhost:4001) | admin / admin |
| Prometheus | [http://localhost:9090](http://localhost:9090) | — |
| Grafana | [http://localhost:3000](http://localhost:3000) | admin / admin |
| Gubernator Metrics | [http://localhost:4002/metrics](http://localhost:4002/metrics) | — |
| Health Check | [http://localhost:4002/health](http://localhost:4002/health) | — |

---

## Grafana Dashboard

The **Gubernator — Cluster Overview** dashboard is provisioned automatically. It shows:

```
┌────────────────────────────────────────────────────────────────┐
│  Active Nodes  │  Total Tasks  │  Status  │  Goroutines        │
│      ██ 1      │     ██ 3      │  ✅ UP   │      ██ 12         │
├────────────────────────────────────────────────────────────────┤
│  Nodes & Tasks Over Time        │  Memory Usage                │
│  ─────────────────────────────  │  ─────────────────────────── │
│  nodes ─────── 1                │  heap ────────────────        │
│  tasks ╱──────╱ 3               │  sys  ─────────────────       │
├────────────────────────────────────────────────────────────────┤
│  Goroutines Over Time  │  GC Rate  │  GC Pause Duration        │
└────────────────────────────────────────────────────────────────┘
```

Panels included:

| Panel | Metric | Type |
|-------|--------|------|
| Active Nodes | `gbnt_total_nodes` | Stat |
| Total Tasks | `gbnt_total_tasks` | Stat |
| Gubernator Status | `up{job="gubernator"}` | Stat (UP/DOWN) |
| Goroutines | `go_goroutines` | Stat |
| Nodes & Tasks Over Time | `gbnt_total_nodes`, `gbnt_total_tasks` | Time series |
| Memory Usage | `go_memstats_alloc_bytes`, `go_memstats_sys_bytes` | Time series |
| Goroutines | `go_goroutines` | Time series |
| GC Rate | `rate(go_gc_duration_seconds_count[5m])` | Time series |
| GC Pause Duration | `go_gc_duration_seconds` p50/p99 | Time series |

---

## Tear Down

```bash
cd monitoring/
docker compose down       # stop containers, keep volumes
docker compose down -v    # stop containers AND delete volumes (reset all data)
```
