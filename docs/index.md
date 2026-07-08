# <img src="gubernator-icon.png" alt="Gubernator Icon" width="40" style="vertical-align: middle;"> Gubernator (gbnt)

Gubernator is a **"Goldilocks" container orchestrator** built in Go — combining the **simplicity of Docker Swarm** (native Compose support, easy cluster joining) with the **flexibility of Nomad** (task-based logic, hardware/AI targeting via labels).

Themed around the **Roman Empire**, Gubernator manages containers across a fleet of nodes ("Centurions") from a central API ("The Senate"), now with a **built-in local executor** so a single node can run a complete cluster out of the box.

---

## Key Features

| Feature | Description |
|---------|-------------|
| **Single binary** | `gbnt` runs as Manager *and* Worker |
| **Docker Compose native** | Deploy any `docker-compose.yml` directly |
| **Single-node mode** | No workers needed — the Manager runs containers locally |
| **Built-in executor** | Passes `ports`, `environment`, `volumes`, and `command` to Docker |
| **Flutter Web UI** | Live Material Design 3 dashboard with compose editor, clickable port links, dark/light themes, and user settings |
| **Ingress + DNS** | Auto-configures CoreDNS and Caddy as containers start |
| **Secure API** | Bearer token auth on port 4000, Basic Auth on Web UI |
| **Observability** | Prometheus metrics, Swagger, and health on port 4002 |
| **SRE Monitor** | One-command deploy: cAdvisor + Prometheus + Grafana + Loki + Promtail |

---

## Port Architecture

| Port | Service | Auth |
|------|---------|------|
| `:4000` | REST API (CLI endpoint) | `Authorization: Bearer <GBNT_API_TOKEN>` |
| `:4001` | Web UI Dashboard | HTTP Basic Auth (`GBNT_WEB_USER` / `GBNT_WEB_PASSWORD`) |
| `:4002` | Telemetry, Swagger, Health | Public (internal monitoring only) |

---

## Quickstart — Single Node

```bash
# 1. Clone and compile
git clone https://github.com/mario-ezquerro/gubernator.git
cd gubernator
go build -o gbnt ./cmd/gbnt

# 2. Start the Manager (with Web UI)
GBNT_API_TOKEN=admin \
GBNT_WEB=true \
GBNT_WEB_USER=admin \
GBNT_WEB_PASSWORD=admin \
./gbnt serve

# 3. In a second terminal — register the local node as worker
export GBNT_API_TOKEN=admin
./gbnt legion init
./gbnt legion join --token <TOKEN> --manager 127.0.0.1:4000

# 4. In a third terminal — deploy a stack (WordPress + MySQL)
./gbnt stack deploy -c examples/example-wordpress/docker-compose.yml wp

# 5. Verify
curl http://localhost:8080          # WordPress setup page
./gbnt task ls                      # See the running tasks
```

Open **[http://localhost:4001](http://localhost:4001)** (admin/admin) to see the live dashboard.

---

## Quickstart — Docker

```bash
docker run -d \
  --name gbnt-manager \
  -p 4000:4000 -p 4001:4001 -p 4002:4002 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e GBNT_API_TOKEN=admin \
  -e GBNT_WEB=true \
  -e GBNT_WEB_USER=admin \
  -e GBNT_WEB_PASSWORD=admin \
  marioezquerro/gubernator:latest serve
```

---

## How Deployment Works

```
gbnt stack deploy -c compose.yml mystack
         │
         ▼
   API (port 4000)
         │
         ▼
   Parse YAML ──► Store Stack + Services + Tasks in SQLite
         │
         ▼
   Scheduler ──► Assigns Tasks to active Nodes
         │
         ├──► Local Executor (Manager, built-in)
         │         └──► docker pull + docker run -p -e -v
         │
         └──► Remote Worker (legion join)
                   └──► polls /v1/node/tasks → docker run
         │
         ▼
   Aqueducts ──► Update CoreDNS hosts + Caddyfile
```

> **New in v1.3.27**: The Manager now includes a **built-in local executor** — containers are started automatically on the manager node without needing an external worker.

---

## Web Dashboard

The Web UI at `:4001` provides full lifecycle management:

- **View** all stacks, services, nodes, and running containers (auto-refreshes every 5s)
- **Clickable port links** — each container's mapped ports appear as clickable chips that open the service in your browser
- **Edit** the compose YAML directly in the browser (syntax-highlighted editor)
- **Save & Redeploy** — stops old containers and launches new ones in one click
- **Stop** individual containers from the tasks table
- **Delete** stacks with automatic container cleanup

---

## SRE Monitoring Stack

Deploy a full observability stack with one command:

```bash
./gbnt monitor init      # Deploy Prometheus, Grafana, Loki, cAdvisor, Promtail
./gbnt monitor status    # Check health of monitoring containers
./gbnt monitor stop      # Tear down the stack
```

| Service | Port | Purpose |
|---------|------|---------|
| cAdvisor | `:8081` | Container resource metrics |
| Prometheus | `:9090` | Metrics collection |
| Grafana | `:3000` | Dashboards (admin/admin) |
| Loki | `:3100` | Log aggregation |
| Promtail | — | Log shipping |

---

## API Documentation

While `./gbnt serve` is running, access:

- **Swagger UI**: [http://localhost:4002/swagger/index.html](http://localhost:4002/swagger/index.html)
- **Health**: [http://localhost:4002/health](http://localhost:4002/health)
- **Metrics**: [http://localhost:4002/metrics](http://localhost:4002/metrics)

---

## Documentation

- [Installation Guide](install.md) — Download pre-built binaries or compile from source
- [CLI Reference](cli.md) — All `gbnt` commands explained
- [Architecture](architecture.md) — Deep dive into how Gubernator works
- [Web UI](web-ui.md) — Dashboard features and usage
- [Examples](examples.md) — Step-by-step tutorials from basic to SRE-grade

---

## Current Development State

> Gubernator **v1.5.0** — Phases 1–11 complete including Flutter Web UI, clickable port links, and built-in SRE Monitoring Stack.

**[View the complete Roadmap](roadmap.md)**
