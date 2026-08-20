# Gubernator (gbnt) - Project Blueprint & Roadmap

Gubernator is a powerful "Goldilocks" orchestrator that combines the **simplicity of Docker Swarm** (native Compose support, easy cluster joining) with the **flexibility of Nomad** (task-based logic, labels for hardware/AI targeting).

## 🏛 Technical Foundation

* **Language:** Go (Golang)
* **State:** SQLite (Centralized on Manager, with local cache on Workers for resilience)
* **API:** Secured REST (Port 4000)
* **Web UI:** Flutter Web Dashboard with Material Design 3 (Port 4001)
* **Observability:** OpenTelemetry + Prometheus, Swagger, Healthchecks (Port 4002)
* **Engine:** Docker Engine API interaction

## 🗺 Development Roadmap: The Road to Rome

The development is divided into "Campaigns" (Sprints):

### Phase 1: The Foundation (The City-State)
*Goal: A single node running the API and managing local containers via `gbnt`.*
* **Gubernator Core:** Setup the Go project structure and the SQLite schema for tracking "Legions" (Services) and "Centurions" (Nodes).
* **The Forum (API):** Implement the REST server on port 4000. Integrate **swag** for automatic Swagger UI generation.
* **Local CLI:** Build the initial `gbnt` binary to talk to the local API.
* **The Docker Bridge:** Logic to translate a service request into a `docker-api` container creation.

### Phase 2: The Legion (Clustering & Networking)
*Goal: Multi-host communication and node registration.*
* **Cluster Logic:** Implement `gbnt legion init` and `join`.
* **Node Registry:** Nodes must "phone home" to the Manager’s API to register status and system info.
* **Join Tokens:** Implementation of a simple JWT or secret-based handshake for `join-token`.
* **Heartbeat System:** Manager tracks node availability (Active/Pause/Drain).

### Phase 3: The Command (Compose & Labels)
*Goal: Deploying complex stacks and targeting specific hardware.*
* **Stack Parser:** Implement `gbnt stack deploy`. Uses a Go library to parse `docker-compose.yml`.
* **Label Engine:** Logic to read `deploy.placement.constraints` from the Compose file and match them against Node labels (e.g., `gpu=true`, `arch=arm64`).
* **Scheduler MVP:** A simple "Least Loaded" or "Spread" algorithm to decide which node gets which container.

### Phase 4: The Watchtowers (Observability & Health)
*Goal: Telemetry and self-healing.*
* **OpenTelemetry Integration:** Export metrics (CPU, RAM, Uptime) to port 4002.
* **Healthchecks:** The Manager polls the `/health` of containers. If one falls, the Governor restarts it.
* **Prometheus Scraper:** Ensure the 4002 output is formatted correctly for Prometheus discovery.

### Phase 6-8: The Senate Mandate & Security
*Goal: Complete API, CLI context management, and Asymmetric Security.*
* **Full CLI Parity:** Implementation of full CRUD for Stacks, Services, Nodes, and Tasks.
* **Security & Isolation:** Asymmetric architecture implementing Bearer tokens (`GBNT_API_TOKEN`) for Port 4000, Basic Auth for Port 4001, and exposing Port 4002 completely isolated for internal monitoring.
* **Remote Contexts:** CLI authentication via `~/.gbntctl/config` with `gbnt config use-context`.

## 🛠 Enhanced Features (The "Nomad-Hybrid" Touch)

1. **Binary Portability:** The `gbnt` binary acts as both the Manager (API + DB) and the Worker (Agent) to simplify deployment.
2. **State Persistence:** Workers maintain a local SQLite cache ("Draft" mode) to keep containers running even if connection to the Manager is lost.
3. **Label Naming Convention:** Roman prefix theme for hardware/AI labels:
   * `gbnt.node.role=worker`
   * `gbnt.node.gpu=nvidia`
   * `gbnt.node.zone=europe-1`
4. **Automatic Swagger:** Access `http://localhost:4002/swagger/index.html` for immediate documentation of the `gbnt` API.

## 📋 Initial Database Schema (SQLite)

| Table | Purpose |
| --- | --- |
| **Nodes** | ID, IP, Role (Manager/Worker), Status, Labels (JSON). |
| **Stacks** | Name, Raw Compose File, Deployment Date. |
| **Services** | ID, StackID, Image, Desired Replicas, Constraints. |
| **Tasks** | Individual container instances, NodeID assigned, Status (Running/Dead). |

## 🛡 First Coding Milestone (The "Veni" Sprint)

1. **Initialize Go project** with `go mod`.
2. **Setup framework:** Gin or Echo for the API and GORM for SQLite.
3. **First Endpoint:** `GET /v1/node/ls` (Returns the current host info).
4. **First CLI Command:** Build `gbnt node ls` which calls the endpoint and prints a table in the terminal.

## 👑 Phase 5: The Empire (Expansion Packs & Advanced Architecture)

To ensure Gubernator can handle real-world, production-ready deployments, the following advanced features will be integrated:

### 1. Ingress & Service Discovery (The Aqueducts)
* **CoreDNS Integration:** A minimal Gubernator node deployment will consist of **Gubernator + CoreDNS + Caddy**. CoreDNS will be deployed so that all Docker containers can resolve internal IPs via DNS. Gubernator will act as the source of truth, actively updating CoreDNS records as containers spin up or die.
* **Caddy Ingress Suite:** Full multi-node Caddy cluster proxy management with 7-tab UI visualization (Dashboard, Routes, Caddyfile, TLS Certs, Access Logs, Log Config, Prometheus Metrics), Root CA trust installation, and complete TLS certificate lifecycle management (X.509 inspection, forced rotation/renewal, domain `.crt` download, custom cert & key upload, and orphan pruning). Full specification detailed in [`SPEC-caddy.md`](SPEC-caddy.md).

### 2. High Availability / HA (The Senate)
* **Distributed SQLite:** To eliminate the single point of failure (SPOF) of a single Manager, Gubernator can evolve to use **rqlite** or **dqlite** (SQLite over Raft). This allows for a multi-manager setup (e.g., 3 Managers) keeping the relational simplicity while providing fault tolerance.

### 3. Secret Management (The Praetorian Guard)
* **Secret Vault:** A mechanism to securely inject passwords or certificates (e.g., encrypted variables stored in the SQLite DB) into containers, keeping them out of plaintext `docker-compose.yml` files.

### 4. Volumes & Persistence (The Granaries)
* **Storage Affinity:** The Scheduler will be aware of local persistent volumes. If a container with a bound local volume restarts, Gubernator will ensure it schedules back onto the exact same node where its physical data resides.

### 5. Rolling Updates (Zero-Downtime Deployments)
* **Update Strategy:** When a stack is updated with a new image, the tasks will undergo a **Rolling Update**. Containers will be updated sequentially, waiting for health checks to pass before taking down older instances to ensure zero downtime.

### 6. SRE Monitor Stack (`gbnt monitor init`)
* **One-command observability:** `gbnt monitor init` deploys the full SRE stack on the Manager: **cAdvisor** (container metrics on `:8081`), **Prometheus** (metrics collection on `:9090`), **Grafana** (dashboards on `:3000` with pre-configured Prometheus + Loki datasources), **Loki** (log aggregation on `:3100`), **Promtail** (log shipping), and **Jaeger** (distributed tracing via OTLP gRPC `:4317`, OTLP HTTP `:4318`, and UI on `:16686` / `/jaeger/`). Includes `examples/example-jaeger` (`jaeger.gbnt.local`) for 3-service tracing and OpenTelemetry traffic generator scripts (`generate_traces.py` & `send_traces.sh`).
* **Lifecycle management:** `gbnt monitor status` for container health, `gbnt monitor stop` to tear down all monitoring containers.
* **Dedicated network:** All containers run on the `gbnt-monitor-net` Docker network.
* **Config auto-generation:** Config files for all services generated in `~/.gbnt/monitor/`.

### 7. Clickable Port Links in Dashboard
* **Port chips:** The Flutter dashboard's tasks table displays each container's mapped ports as clickable `ActionChip` widgets. Clicking a port opens `http://<nodeIP>:<hostPort>` in a new browser tab. Supports multiple ports per container.

### 8. Bulk Actions for Containers
* **Batch operations:** Tasks table features checkboxes to select multiple containers (working across searches/filters) and perform bulk Start, Stop, Restart, or Remove operations with a confirmation toolbar.

### 9. Legions / Centurions Dashboard Split Ratio
* **1/3 vs 2/3 ratio:** Stacks (Legions) panel defaults to 1/3 width and Nodes (Centurions) panel defaults to 2/3 width, with dynamic drag handle resizing preserved.

### 10. Force Leave Worker Stack Purging
* **Smart drainage:** Executing `Force Leave` drains user tasks to remaining active nodes, while worker system stacks (`CORE-GBNT` and `[SRE] Monitor`) are terminated and automatically deleted from DB and Stacks view.

### 11. Sloth SLO Engine & Error Budget Tracking (`gbnt slo`)
* **Google SRE Multi-Burn-Rate Alerts:** Native integration of Sloth (`slok/sloth`) into Gubernator's core engine. Translates `gbnt.slo.*` Compose service labels into production-grade Prometheus recording and alerting rules, calculating real-time Error Budget % and multi-window burn rates via REST API (`/v1/slo`) and CLI (`gbnt slo ls`, `gbnt slo sync`).

### 12. Git Commits & Release Tag Quality
* **Descriptive Commit Messages:** Whenever creating commits and tags for version bumps, the commit message MUST be detailed, informative, and explicitly describe what changed (e.g. `feat(scope): ...` or `fix(component): ...`). Avoid generic messages like `bump version` or `fix bug`.

### 13. Enterprise Active Directory & LDAP Authentication + RBAC (`v2.20.0`)
* **Multi-Server Enterprise Directory:** Connects Gubernator to multiple Active Directory / OpenLDAP servers with TLS/LDAPS (636) and StartTLS support, custom bind accounts, base search filters, and live connection diagnostics.
* **Role-Based Access Control (RBAC):** Group DN mapping to three distinct operational tiers:
  * 👑 `admin`: Unrestricted full access across cluster nodes, stacks, container shells, Caddy TLS certificates, CoreDNS configuration, and LDAP security.
  * ⚡ `operator`: Stacks deployment/redeploy, task lifecycle (start, stop, restart), container logs, and terminal access without cluster/security mutation rights.
  * 👁️ `readonly`: Visual-only audit access across overview, stacks, tasks, topology, Caddy routes, Grafana, Jaeger, and SLOs (all mutating actions disabled).
* **Dual Emergency Auth & JWT Sessions:** Seamless fallback to local administrator (`admin` / `admin`) with 24-hour cryptographically signed HMAC-SHA256 JWT tokens.
* **Dedicated Security UI:** Modern Directory Server management screen with "Test Connection" diagnostic tool and visual profile chips.

### 14. Dedicated Loki Logs Explorer & Monitoring Reorganization (`v2.21.0`)
* **Navigation Reorganization:** Separated metrics dashboards (**Monitoring**, embedding Grafana) from the brand-new dedicated **Loki Logs Explorer** panel (`label: 'Loki Logs'`).
* **Multi-Dimensional Log Filtering:** Query cluster-wide logs aggregated by Loki and Promtail with multi-dimensional filtering by Centurion node, container/service, log level (`ERROR`, `WARN`, `INFO`), stream (`stdout`, `stderr`), time range (`5m`, `15m`, `1h`, `6h`, `24h`, `7d`), and keyword/regex with live text highlighting.
* **Live Tailing Stream:** One-click live tail mode automatically refreshing logs every 3 seconds.
* **Terminal Console & Export:** Monospace console view with structured stream metadata inspection, one-click raw log copying, and direct `.log` file export (`GET /api/logs/export`).
### 15. Enterprise Ansible Playbooks & Multi-Distro Cluster Automation (`v2.22.0`)
* **Multi-Distribution Automation:** Complete automated provisioning suite in `ansible/` supporting Debian/Ubuntu (20.04/22.04/24.04, 11/12) and RedHat/Rocky/AlmaLinux/Fedora (8/9).
* **System Hardening & Kernel Tuning:** Automates loading of container & overlay modules (`overlay`, `br_netfilter`, `nf_conntrack`), sysctl network tuning (`net.bridge.bridge-nf-call-iptables`, `net.ipv4.ip_forward`), and firewall port rules (UFW / Firewalld).
* **Docker CE Engine Automation:** Official GPG keys/repositories setup, daemon.json log rotation tuning (`10m`, `3` files), user group permissions, and service persistence.
* **Weave Net & Wave Scope Integration:** Deploys containerized Weave Scope probe & app (`marioezquerro/scope:latest`) with host PID/network sharing for full cluster topology mapping.
* **Full Stack Orchestration:** Configures systemd units (`gbnt-manager.service`, `gbnt-worker.service`), automatic join token discovery, and executes SRE Observability stack setup (`gbnt monitor init`).

### 16. Multi-Cloud Terraform Infrastructure Suite (`v2.23.0`)
* **Multi-Cloud IaC Automation:** Production-grade Terraform modules in `terraform/` for **AWS**, **Hetzner Cloud**, **DigitalOcean**, **Google Cloud Platform (GCP)**, and **Proxmox VE**.
* **Automated Ansible Inventory Bridge:** Every Terraform provider module automatically populates `ansible/inventory.ini` with provisioned public/private IPs, credentials, and node roles on `terraform apply`.
* **Zero-Touch Infrastructure Pipeline:** Enables full multi-cloud cluster provisioning from bare metal / cloud VMs to fully orchestrated Gubernator clusters in 2 simple commands (`terraform apply && ansible-playbook site.yml`).

### 17. Persistent Storage & Backups Subsystem — "The Granaries" (`v2.24.0`)
* **Shared Storage Mobility (`/var/contenedores`)**: Enables multi-node persistent volume mobility across Centurions via shared network mounts (NFS, GlusterFS, CephFS, CIFS) or local volumes.
* **Volume Explorer**: Automatic cluster-wide discovery and disk usage calculation for Docker Named Volumes, Shared Pools, and Host Bind Mounts.
* **Point-in-Time Compressed Backups**: Instant creation of `.tar.gz` archives with cryptographic SHA-256 integrity verification, direct browser downloads, and external backup uploads.
* **Zero-Downtime / Consistent Freeze**: Optional container pause (`docker pause` -> archive -> `docker unpause`) for 100% consistent database backups (Postgres, MySQL, MariaDB, SQLite).
* **Automated Cron & Retention Policies**: Background scheduler daemon running periodic backup policies with automatic rotation and pruning of older archives.
* **Storage Pools Health Matrix**: Live diagnostic panel verifying `/var/contenedores` mount accessibility, read/write permissions, and disk capacity across all cluster nodes.
* **Full CLI Parity**: Dedicated commands for `gbnt volume ls`, `gbnt backup ls`, `gbnt backup create`, `gbnt backup restore`, and `gbnt backup schedule ls`.

### 18. Image Security, SBOM & Cryptographic Signing — "The Imperial Seal" (`v2.25.0`)
* **Vulnerability Scanning (CVEs)**: Automated scanning of container images deployed in stacks with CVSS scoring, severity counts, affected packages, and fixed version tracking.
* **Software Bill of Materials (SBOM)**: Deep dependency analysis producing standard **CycloneDX JSON** and **SPDX JSON** documents with software license audit compliance.
* **Cosign Cryptographic Signing**: In-cluster ECDSA P-256 keypair generation, image digest signing, and verification of container signatures.
* **Security Gatekeeper (Admission Controller)**: Pre-deployment policy engine capable of blocking unverified/unsigned images or containers containing unpatched critical CVEs.
* **Full CLI Parity**: Dedicated commands for `gbnt scan`, `gbnt sbom`, `gbnt image sign`, `gbnt image verify`, `gbnt security policy`, and `gbnt security key`.


