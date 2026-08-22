# <img src="docs/gubernator-icon.png" alt="Gubernator Icon" width="40" style="vertical-align: middle;"> Gubernator (gbnt)

[![GitHub Release](https://img.shields.io/github/v/release/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/releases)
[![Docker Image](https://img.shields.io/docker/v/marioezquerro/gubernator?style=flat-square&color=blue&logo=docker)](https://hub.docker.com/repository/docker/marioezquerro/gubernator/general)
[![Go Version](https://img.shields.io/github/go-mod/go-version/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/blob/main/go.mod)
[![Go Report Card](https://goreportcard.com/badge/github.com/mario-ezquerro/gubernator?style=flat-square)](https://goreportcard.com/report/github.com/mario-ezquerro/gubernator)
[![License](https://img.shields.io/github/license/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/blob/main/LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/mario-ezquerro/gubernator/test.yml?branch=main&style=flat-square)](https://github.com/mario-ezquerro/gubernator/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-MkDocs-blue?style=flat-square)](https://mario-ezquerro.github.io/gubernator/)
[![GitHub issues](https://img.shields.io/github/issues/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/pulls)
[![GitHub stars](https://img.shields.io/github/stars/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/network)
[![Docker Pulls](https://img.shields.io/docker/pulls/marioezquerro/gubernator?style=flat-square&logo=docker)](https://hub.docker.com/r/marioezquerro/gubernator)
[![Docker Image Size](https://img.shields.io/docker/image-size/marioezquerro/gubernator/latest?style=flat-square&color=blue&logo=docker)](https://hub.docker.com/r/marioezquerro/gubernator)
[![Go Reference](https://img.shields.io/badge/go-reference-blue?style=flat-square&logo=go)](https://pkg.go.dev/github.com/mario-ezquerro/gubernator)
[![GitHub contributors](https://img.shields.io/github/contributors/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/graphs/contributors)
[![GitHub repo size](https://img.shields.io/github/repo-size/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator)
[![GitHub last commit](https://img.shields.io/github/last-commit/mario-ezquerro/gubernator?style=flat-square)](https://github.com/mario-ezquerro/gubernator/commits/main)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/mario-ezquerro/gubernator)


Gubernator is a powerful "Goldilocks" orchestrator that combines the **simplicity of Docker Swarm** (native Compose support, easy cluster joining) with the **flexibility of Nomad** (task-based logic, labels for hardware/AI targeting).

Themed around the **Roman Empire**, Gubernator aims to manage your containers robustly across a fleet of nodes ("Centurions") managed by a central API ("The Senate").

---

##  Architecture Overview

Gubernator operates using a single, portable binary (`gbnt`) that can run as either a Manager or a Worker. 
* **API & CLI:** Built with Gin and Cobra.
* **State:** Powered by SQLite and GORM.
* **Container Engine:** Direct communication with the Docker Engine.
* **Web Dashboard:** Flutter Web with Material Design 3 (embedded into the Go binary).
* **Enterprise Security & RBAC:** Multi-Server Active Directory / OpenLDAP authentication with LDAPS/StartTLS, JWT HMAC-SHA256 sessions, emergency local admin, and dynamic 3-tier RBAC (`admin`, `operator`, `readonly`) (see [docs/auth-rbac.md](docs/auth-rbac.md)).
* **Image Security, SBOM & Cosign Signing:** Automated CVE vulnerability scanning, CycloneDX & SPDX Software Bill of Materials, Cosign ECDSA cryptographic image signing, and Gatekeeper pre-deployment admission control (see [SPEC-image-security.md](SPEC-image-security.md) and [docs/image-security.md](docs/image-security.md)).
* **Persistent Storage & Point-in-Time Backups:** Shared volume mobility across hosts (`/var/contenedores`), zero-downtime database freeze (`docker pause`), compressed `.tar.gz` backups with SHA-256 integrity, and cron retention policies (see [SPEC-storage-backups.md](SPEC-storage-backups.md) and [docs/storage-backups.md](docs/storage-backups.md)).
* **SLO Engine & Error Budget Tracking:** Sloth-powered Google SRE multi-window multi-burn-rate alerting, Prometheus recording rules, and real-time Error Budget monitoring (see [docs/slo.md](docs/slo.md) and [docs/example-slo.md](docs/example-slo.md)).
* **Ingress & DNS:** Built-in hooks for CoreDNS (internal resolution) and multi-node Caddy Ingress with full 7-tab UI management (see [SPEC-caddy.md](SPEC-caddy.md) and [docs/caddy.md](docs/caddy.md)).

*(See [architecture.md](docs/architecture.md) for a deeper dive).*

---

## 📸 Enterprise Active Directory & RBAC (`v2.20.0`)

| Modern Login Screen & Domain Selector | Security & Active Directory Management |
| :---: | :---: |
| ![Login Screen](docs/images/login_screen.png) | ![Security & AD](docs/images/security_ad.png) |

---

##  Getting Started

### Installation

The `gbnt` CLI tool is compiled as a single, portable binary for Windows, macOS, and Linux.

 **[See the Official Installation Guide](https://mario-ezquerro.github.io/gubernator/install/)** to download and install the binary for your operating system.

If you prefer to compile from source (requires Go 1.24+ and CGO):
```bash
git clone https://github.com/mario-ezquerro/gubernator.git
cd gubernator
go build -o gbnt ./cmd/gbnt
```

Alternatively, you can run Gubernator using Docker via the included multi-stage `Dockerfile`.

**1. Build the Docker Image:**

* **For the local architecture only:**
  ```bash
  docker build -t gbnt:latest .
  ```

* **For multiple architectures (Intel, macOS, Raspberry Pi):**
  We use `docker buildx` to compile for `linux/amd64` (Intel/AMD), `linux/arm64` (macOS Apple Silicon & Raspberry Pi 4+), and `linux/arm/v7` (32-bit Raspberry Pi):
  ```bash
  # Build and check compilation for all targets:
  docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t marioezquerro/gubernator:latest .

  # Build and push to Docker Hub:
  docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t marioezquerro/gubernator:latest --push .
  ```


**2. Run the Manager API via Docker:**
Because Gubernator manages Docker containers, it needs access to the local Docker socket. We also expose ports `4000` (CLI), `4001` (Web UI), and `4002` (API/Swagger, Health, and Telemetry).

```bash
docker run -d \
  --name gbnt-manager \
  -p 4000:4000 \
  -p 4001:4001 \
  -p 4002:4002 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v gubernator-data:/data \
  -v gubernator-home:/root/.gbnt \
  -e GBNT_WEB=true \
  -e GBNT_WEB_USER=admin \
  -e GBNT_WEB_PASSWORD=admin \
  -e GBNT_MONITOR=true \
  -e GBNT_DNS_FORWARDERS="8.8.8.8 1.1.1.1" \
  marioezquerro/gubernator:latest serve
```

> **Important:** The `-v gubernator-data:/data` and `-v gubernator-home:/root/.gbnt` volumes persist your database and configuration files (CoreDNS and SRE stack) across container restarts. This is where Gubernator stores nodes, stacks, tokens, and all configurations. Without them, the cluster state is lost on restart. The `-e GBNT_MONITOR=true` and `-e GBNT_WEB=true` enable the SRE monitoring stack and the Web Dashboard respectively on startup.

**Alternatively, run via Docker Compose:**
You can use the provided `docker-compose.yml` and `.env` files in the root of the repository to start the Manager API easily:

```bash
docker compose up -d
```
**3. Run CLI Commands via Docker:**
You can execute CLI commands directly through the running container:

```bash
docker exec -it gbnt-manager /app/gbnt node ls
```

To retrieve the initial tokens or see the startup logs, especially if running in detached mode (`-d`), you can use:

```bash
# Ver los logs de arranque
docker logs gbnt-manager

# O pedirle los tokens directamente al contenedor
docker exec -it gbnt-manager /app/gbnt legion info
```


> **Note:** When you configure your local `gbnt` CLI using `gbnt config add-context`, the authentication token and server URL are stored locally on your machine in the `~/.gbntctl/config` file.
### Starting the Manager (The Senate)

To initialize the centralized API server on port `4000`:

```bash
./gbnt serve
```

#### 🔐 First Boot — Security Bootstrap

On the **very first start**, Gubernator automatically generates two secure credentials and prints a one-time banner:

```text
╔══════════════════════════════════════════════════════════════════╗
║          🏛  GUBERNATOR — FIRST BOOT CREDENTIALS                ║
╠══════════════════════════════════════════════════════════════════╣
║  API TOKEN  : 4a8f3c1d2e9b...                                    ║
║                                                                  ║
║  Save this token! It will NOT be shown again.                    ║
║  Use it to configure your remote gbnt CLI:                      ║
║                                                                  ║
║  gbnt config add-context myserver \                             ║
║      --server http://<MANAGER-IP>:4000 \                        ║
║      --token 4a8f3c1d2e9b...                                     ║
╚══════════════════════════════════════════════════════════════════╝
```

**Both credentials are persisted in the SQLite database** (`/data/gubernator.db`) and survive container restarts. You do not need to regenerate or provide them again.

| Credential | Purpose | How to retrieve |
|---|---|---|
| **API Token** | Bearer auth for the REST API (port 4000) — used by the `gbnt` CLI | Shown once at first boot. Retrieve later with `gbnt legion info` (localhost only) |
| **Join Token** | Allows worker nodes to register into the cluster | `gbnt legion join-token` or `gbnt legion info` (localhost only) |

To see both tokens and the ready-to-use commands at any time:
```bash
gbnt legion info
```

---

##  CLI Usage & Examples

By default, the CLI connects to `http://localhost:4000`. You can configure it to act as a remote `gbntctl` client by managing contexts.

### Context Management (Remote CLI)

Settings are stored in `~/.gbntctl/config` (similar to Kubeconfig). This allows you to manage **remote Gubernator managers** from any machine.

**Add a context (connect to a remote manager):**
```bash
gbnt config add-context production \
    --server http://192.168.1.10:4000 \
    --token <API_TOKEN>
```
> Get `<API_TOKEN>` from the first-boot banner or by running `gbnt legion info` on the Manager host.

**Other context commands:**
```bash
gbnt config get-contexts      # List all configured contexts
gbnt config use-context prod  # Switch to a different manager
gbnt config current-context   # Show the currently active context
```

### List Nodes
To see all nodes (Centurions) currently registered in the cluster:

```bash
./gbnt node ls
```

**Output Example:**
```text
ID                   IP            ROLE     STATUS 
node-local-manager   127.0.0.1     manager  active 
node-worker-pi4      192.168.1.20  worker   active 
```

### Clustering (The Legion)

To form a cluster, you must initialize the "Legion" from the Manager node to retrieve the secure Join Token.

```bash
# On the Manager node — shows both tokens and ready-to-use commands
gbnt legion info
```

*Output example:*
```text
╔══════════════════════════════════════════════════════════╗
║         🏛  GUBERNATOR — CLUSTER INFO                   ║
╠══════════════════════════════════════════════════════════╣
║  JOIN TOKEN : a3f8c1d2e4b5...                            ║
║  API TOKEN  : 4a8f3c1d2e9b...                            ║
╠══════════════════════════════════════════════════════════╣
║  Add a WORKER node:                                      ║
║  > gbnt legion join --token a3f8... --manager <IP>:4000  ║
║                                                          ║
║  Configure remote CLI:                                   ║
║  > gbnt config add-context myserver --server http://...  ║
╚══════════════════════════════════════════════════════════╝
```

Once you have both tokens, join any machine as a Worker (Centurion):

```bash
# On the worker host
gbnt legion join \
    --token <JOIN_TOKEN> \
    --api-token <API_TOKEN> \
    --manager 192.168.1.100:4000
```

*This will:*
1. Authenticate the node using the join token.
2. Register it in the Manager's SQLite DB with its real IP address.
3. Start a background heartbeat service (every 10s) so the Manager tracks its availability.
4. Start the task executor loop (every 5s) to pull and run assigned containers.

> **Security note:** The Join Token is only used during the `legion join` handshake. All subsequent communication (heartbeat, task status) uses the Bearer API Token.

### Stack Deploy (The Command)

You can deploy standard `docker-compose.yml` files. The built-in Scheduler will parse the file, look for placement constraints, and assign tasks to the appropriate Centurions.

Create a sample `docker-compose.yml`:
```yaml
services:
  web:
    image: nginx:latest
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.gbnt.node.role == worker
```

Deploy the stack:
```bash
./gbnt stack deploy -c docker-compose.yml mystack
```

### Service Level Objectives (SLOs) & Error Budget Tracking

Gubernator features native SLO calculation, Error Budget tracking, and interactive visualizations powered by **Sloth** ([github.com/slok/sloth](https://github.com/slok/sloth)) and inspired by **Pyrra** ([github.com/pyrra-dev/pyrra](https://github.com/pyrra-dev/pyrra)).

Features built-in SLI templates (`caddy-http`, `http-status`, `latency-p99`, `grpc`), `latency` indicator thresholds, composite **User Journeys**, deployment event correlation, PromQL backtesting/validation, auto-generated Grafana dashboards, and a 5-tab Web Dashboard Suite with search, sorting, and historical trend charts.

Simply add `gbnt.slo.*` labels to your service in `docker-compose.yml`:

```yaml
services:
  payment-api:
    image: payment-api:latest
    labels:
      gbnt.slo.enable: "true"
      gbnt.slo.target: "99.9"
      gbnt.slo.window: "30d"
      gbnt.slo.template: "caddy-http"
      gbnt.slo.journey: "Checkout Flow"
```

*Commands:*
```bash
# List active SLOs and real-time Error Budget % remaining
gbnt slo ls

# Manually trigger SLO rules generation for Prometheus & Grafana
gbnt slo sync
```

*Output:*
```text
 Stack 'mystack' deployed successfully!
The Governor has dispatched the Centurions to schedule the tasks.
```

### Telemetry & Metrics (The Watchtowers)

Gubernator comes with built-in Prometheus metrics and health checks. When the manager starts, a dedicated telemetry server is exposed on port `4002`.

You can view the raw metrics or point your Prometheus scraper to:
```bash
curl http://localhost:4002/metrics
curl http://localhost:4002/health
```

*These metrics include real-time counts of nodes, tasks, and system performance.*

### The Executor (Docker Bridge)

Gubernator runs native Docker containers. Once a stack is deployed, the Centurions (Worker nodes) pull their assigned tasks and talk directly to the local Docker socket to:
1. `docker pull` the required images.
2. `docker run -d` the containers, labeling them automatically with the Gubernator Task ID.
3. Automatically inject `--dns <CoreDNS_IP>` so every container inherently uses Gubernator's DNS.

You don't need any special runners; if the machine has `dockerd` running, Gubernator can orchestrate it.

### Ingress & Service Discovery (The Aqueducts)

Gubernator actively manages its own internal DNS and external ingress routing by dynamically writing configuration files for **CoreDNS** and **Caddy**.

When a task starts, the worker extracts its internal Docker IP. Gubernator then generates two files automatically in its working directory:
1. `gubernator.hosts` - A file you can configure CoreDNS (using the `hosts` plugin) to auto-load. It creates internal domains like `web.mystack.gbnt` pointing directly to the active containers.
2. `Caddyfile` - If a service is deployed with the constraint `ingress.host == api.example.com`, Gubernator writes a Caddyfile configuring Caddy to reverse-proxy `api.example.com` to the internal `gbnt` DNS name.

To complete the Empire Trifecta, simply run Caddy and CoreDNS in the same directory alongside the Manager, and they will pick up these auto-generated routing tables!

> **Pro Tip (Host DNS):** Want to access `*.gbnt.local` and `*.gbnt` domains from your host browser without touching `/etc/hosts`? Configure your OS resolver! On macOS, just run:
> `sudo mkdir -p /etc/resolver && sudo sh -c 'echo "nameserver 127.0.0.1" > /etc/resolver/gbnt' && sudo sh -c 'echo "nameserver 127.0.0.1" > /etc/resolver/gbnt.local'`

---

##  Web UI Dashboard (Flutter)

Gubernator includes a premium, built-in **Flutter Web Dashboard** with **Material Design 3** to visualize and manage your cluster. It is disabled by default to keep the binary lightweight and secure.

**Features:**
- 📊 **Real-time stats** — Nodes, Stacks, Services, Tasks counters with auto-refresh
- 📝 **Compose editor** — View, edit, save, and redeploy stack YAML files
- ⚙️ **Settings gear icon** — User profile, password change, and dark/light theme toggle
- 🌙 **Dark / Light themes** — Material Design 3 theming with smooth transitions
- 📱 **Responsive layout** — Works on desktop, tablet, and mobile browsers

To activate the Web UI on **port 4001**, you must pass the `GBNT_WEB=true` flag and credentials when starting the Manager:
```bash
GBNT_WEB=true GBNT_WEB_USER=admin GBNT_WEB_PASSWORD=supersecreto ./gbnt serve
```
Or, if running via Docker:
```bash
docker run -d -p 4000:4000 -p 4001:4001 \
  -e GBNT_WEB=true -e GBNT_WEB_USER=admin -e GBNT_WEB_PASSWORD=supersecreto \
  gubernator:latest serve
```

Access the dashboard at `http://localhost:4001` and authenticate with the credentials you provided to manage nodes, view running containers, click on port links to open services in your browser, and stop tasks dynamically!

---

## 🛡️ SRE Monitoring Stack (`gbnt monitor`)

Gubernator includes a **built-in SRE observability stack** that can be deployed with a single command. No external tooling or Compose files required.

### Deploy on the Manager
```bash
./gbnt monitor init
```

This command deploys 7 containers on a dedicated Docker network (`gbnt-monitor-net`):

| Container | Port | Role |
|-----------|------|------|
| **cAdvisor** | `:8081` | Container CPU, memory, disk, network metrics |
| **Node Exporter** | `:9100` | Host hardware, CPU, memory, disk, and OS network metrics |
| **Prometheus** | `:9090` | Metrics scraping (Gubernator + cAdvisor + Node Exporter + workers) |
| **Grafana** | `:3000` | Dashboards with pre-configured datasources (admin/admin) |
| **Loki** | `:3100` | Log aggregation from all nodes |
| **Promtail** | — | Ships container and system logs to Loki |
| **Jaeger** | `:4317`, `:4318`, `:16686` | Distributed tracing OTLP (gRPC/HTTP) & UI (`/jaeger/`) |

### Management Commands
```bash
./gbnt monitor status   # Check health of all monitoring containers
./gbnt monitor stop     # Tear down the entire stack
```

Configuration files are auto-generated in `~/.gbnt/monitor/` and can be customized.

> 💡 **Try the Jaeger Tracing Example**: See [`examples/example-jaeger`](examples/example-jaeger) (`jaeger.gbnt.local`) for a 3-service distributed tracing demo and traffic generation tools (`python3 generate_traces.py --count 15`).

---

## 🔐 Security & Environment Variables

### Credentials (auto-generated on first boot)

| Credential | Storage | Description |
|---|---|---|
| **API Token** | SQLite DB + `GBNT_API_TOKEN` env | Bearer token required for all API calls on port 4000 |
| **Join Token** | SQLite DB | One-time handshake token for workers joining the cluster |

Both tokens are generated with `crypto/rand` and stored in the `/data/gubernator.db` database. They persist across restarts as long as the volume is mounted.

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GBNT_DATA_DIR` | `/data` | Directory for SQLite DB. Falls back to `.` if `/data` doesn't exist |
| `GBNT_API_TOKEN` | *(auto-generated)* | Override the Bearer token for the REST API |
| `GBNT_WEB` | `false` | Set to `true` to enable the Flutter Web Dashboard on port 4001 |
| `GBNT_WEB_USER` | — | Username for the Web Dashboard Basic Auth |
| `GBNT_WEB_PASSWORD` | — | Password for the Web Dashboard Basic Auth |
| `GBNT_MONITOR` | `false` | Set to `true` to auto-deploy the SRE monitoring stack on startup |
| `GBNT_DNS_FORWARDERS` | `8.8.8.8 1.1.1.1` | Space-separated list of external DNS servers for CoreDNS to use for internet resolution |

### Full Docker run example (all features)

```bash
docker run -d \
  --name gbnt-manager \
  -p 4000:4000 \
  -p 4001:4001 \
  -p 4002:4002 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v gubernator-data:/data \
  -v gubernator-home:/root/.gbnt \
  -e GBNT_WEB=true \
  -e GBNT_WEB_USER=admin \
  -e GBNT_WEB_PASSWORD=admin \
  -e GBNT_MONITOR=true \
  -e GBNT_DNS_FORWARDERS="8.8.8.8 1.1.1.1" \
  marioezquerro/gubernator:latest serve
```

---

##  Commands Reference (CLI)

**🔐 Security & Bootstrap**
* `gbnt legion info` - Show join token + API token + ready-to-use commands. **(Localhost only)**
* `gbnt legion join-token` - Print only the worker join command.

**📡 Context Management (Remote CLI)**
* `gbnt config add-context [name] --server [url] --token [token]` - Add/update a remote manager context.
* `gbnt config get-contexts` - List all configured contexts.
* `gbnt config use-context [name]` - Switch active context.
* `gbnt config current-context` - Show the active context.

**The Legion (Cluster)**
* `gbnt legion init` - Initialize a new cluster (Manager).
* `gbnt legion join --token [t] --api-token [t] --manager [addr]` - Join as a Worker.
* `gbnt legion leave` - Leave the cluster.

**The Centurions (Nodes)**
* `gbnt node ls` - List all nodes.
* `gbnt node inspect [node_id]` - Show detailed info of a node.
* `gbnt node promote [node_id]` - Promote a worker to manager.
* `gbnt node demote [node_id]` - Demote a manager to worker.
* `gbnt node update --availability [active|pause|drain] [node_id]` - Update node status.

**The Commands (Stacks)**
* `gbnt stack deploy -c [file.yml] [name]` - Deploy a compose stack.
* `gbnt stack ls` - List deployed stacks.
* `gbnt stack services [stack_id]` - List services within a stack.
* `gbnt stack rm [stack_id]` - Remove a stack.

**The Cohorts (Services)**
* `gbnt service ls` - List all services.
* `gbnt service ps [service_id]` - List tasks running for a service.
* `gbnt service scale [service_id]=[replicas]` - Scale a service up/down.
* `gbnt service rm [service_id]` - Delete a service.

**SRE Monitor (Observability)**
* `gbnt monitor init` - Deploy the full SRE stack (Prometheus, Grafana, Loki, cAdvisor, Promtail, Node Exporter, Jaeger).
* `gbnt monitor status` - Show status of monitoring containers.
* `gbnt monitor stop` - Stop and remove all monitoring containers.

**GlusterFS Cluster Storage (The Granaries)**
* `gbnt gluster status` - Cluster storage health score, peer mesh, and daemon state.
* `gbnt gluster peer-ls` - List all nodes in the GlusterFS trusted storage pool.
* `gbnt gluster probe [host]` - Add a new node to the trusted storage pool.
* `gbnt gluster detach [host]` - Detach a node from the trusted storage pool.
* `gbnt gluster ls` - List all replicated volumes, capacity usage, and mount points.
* `gbnt gluster create [name]` - Create and tune a 3-way mirrored volume (`Replica 3`).
* `gbnt gluster start [name]` - Start a GlusterFS volume.
* `gbnt gluster stop [name]` - Stop a GlusterFS volume.
* `gbnt gluster heal [name]` - Self-healing diagnostics, split-brain status, and manual sync.
* `gbnt gluster mount [name]` - Auto-mount volume to `/var/contenedores` across all cluster nodes.
* `gbnt gluster rm [name]` - Delete a GlusterFS volume.

**System**
* `gbnt serve` - Start the Manager daemon.
* `gbnt health` - Check local process health (used as Docker HEALTHCHECK).

---

##  API Documentation (Swagger)

Gubernator features auto-generated Swagger documentation. 
While `./gbnt serve` is running, navigate to the following URL in your browser:

 **[http://localhost:4002/swagger/index.html](http://localhost:4002/swagger/index.html)**

From the Swagger UI, you can directly test endpoints.

---

## 📊 Telemetry, Adoption Metrics & Privacy Transparency

Gubernator values **openness, privacy, and full transparency**. You can view live community adoption and release metrics directly inside the Web Dashboard (**Settings ➔ About & Metrics**), via CLI (`gbnt version --metrics`), or through the REST API (`GET /api/system/adoption`).

```text
📊 Community Adoption & Release Metrics:
  • Total Releases:     88 Published
  • Total Downloads:    13+ Multi-platform Binaries
    - Linux:            AMD64 & ARM64
    - macOS:            Apple Silicon & Intel
    - Windows:          x64 Native EXE
  • GitHub Stars:       23 ⭐
  • GitHub Forks:       3 🍴
```

### 🛡️ Data Origin & Zero Cluster Telemetry Guarantee

1. **Transparent Public Data Sources:**
   * Download counts and release history are queried transparently from the official public [GitHub Releases API](https://api.github.com/repos/mario-ezquerro/gubernator/releases). No private tracking cookies, pixels, or intrusive analytics scripts are used.
2. **100% On-Premise & GDPR Compliant:**
   * Gubernator **NEVER** sends, tracks, or logs your container images, environment variables, passwords/secrets, application database contents, or internal network topologies to external servers. All cluster operations remain 100% local to your hosts.
3. **Air-Gapped & Complete Opt-Out:**
   * For isolated or air-gapped environments without internet access, you can completely disable external version and release checks by setting the standard environment variable:
     ```bash
     export DO_NOT_TRACK=1
     # or
     export GBNT_TELEMETRY=false
     ```

---

## 🗺 Current Roadmap State

Gubernator's development is divided into "Campaigns". We've completed up to **Phase 23**, including full CLI parity, Native Docker Engine execution, CoreDNS/Caddy Ingress Automation, Asymmetric Port Security, Flutter Web Dashboard, built-in SRE Monitoring Stack, Google SRE Sloth SLO Engine, Enterprise Active Directory / LDAP Authentication + RBAC (`v2.20.0`), Dedicated Loki Logs Explorer (`v2.21.0`), Multi-Distro Ansible Automation (`v2.22.0`), Multi-Cloud Terraform Suite (`v2.23.0`), Persistent Storage & Backups ("The Granaries") (`v2.24.0`), Image Security, SBOM & Cosign Signing ("The Imperial Seal") (`v2.25.0`), Dedicated Compose Studio & Copilot (`v2.27.0`), Network Mounts & `/etc/fstab` Management (`v2.28.0`), Transparent Adoption Metrics & Privacy (`v2.29.0`), GlusterFS Cluster Storage Subsystem (`v2.30.0`), and Host & Cluster Disk Monitoring, SLO Alerting & Storage Dashboarding (`v2.31.0`).

**[View the complete Roadmap and completed features here](https://mario-ezquerro.github.io/gubernator/roadmap/)**


