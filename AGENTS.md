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

### 19. Dedicated Compose Studio & Gubernator Copilot Subsystem (`v2.27.0`)
* **Dedicated Navigation Entry:** Full-screen IDE workspace accessible directly below **Security & Directory** in the dashboard sidebar.
* **Stack & Template Management:** Instant switching between existing cluster stacks or authoring new stacks from production blueprints (Web Ingress, Postgres Storage, SRE Microservice, Gatekeeper Signed App, GPU AI Task).
* **Smart Autocompletion & Suggestion Bar:** Contextual keyword chips (`ingress.host`, `gbnt.caddy.port`, `gbnt.slo.*`, `gbnt.security.*`, `deploy.placement`, `/var/contenedores/`) that filter as you type and insert snippets with correct YAML indent.
* **Gubernator Copilot Side Panel:** 6-tab visual wizard for Caddy Ingress, Sloth SLOs, Security Gatekeeper, live Centurion Node hardware affinity, and Storage Granaries.
* **Full Stack Lifecycle:** One-click Save Compose, Save & Deploy / Redeploy, Reset, Import from `.yml`, and Export `.yml` archive.
* **Ansible Multi-Distro Automation:** Complete cluster bootstrap playbooks in `ansible/` (and `ansible-playbooks/`) for Debian/Ubuntu and RHEL/CentOS/Rocky/AlmaLinux/Fedora with SSH, Docker CE, Weave Scope, and Gubernator services.

### 20. Network Mounts & `/etc/fstab` Management Subsystem (`v2.28.0`)
* **Multi-Protocol Network Storage:** Full management and auto-mounting of **NFS (v3/v4)**, **Windows / NAS Samba (CIFS)**, **S3 Object Storage (FUSE / s3fs)** for AWS/MinIO/Wasabi/Cloudflare R2, **GlusterFS**, and local POSIX block devices.
* **Granaries `/var/contenedores` Mobility Root:** Seamlessly links remote storage shares to `/var/contenedores`, enabling multi-node container data mobility and zero-data-loss task rescheduling.
* **Safe `/etc/fstab` Synchronization:** Automated discovery and safe editing of host `/etc/fstab` with tagged block delimiters (`# BEGIN GBNT MOUNT`) and timestamped backup archives (`/etc/fstab.bak.<ts>`).
* **Interactive Protocol Wizard & Live Diagnostics:** 4-protocol creation wizard with latency probes, read/write verification (`.gbnt-rw-probe`), disk capacity calculation, and raw `/etc/fstab` syntax inspector.
* **Full CLI Parity:** Dedicated commands for `gbnt mount ls`, `gbnt mount add`, `gbnt mount rm`, `gbnt mount mount <id>`, `gbnt mount unmount <id>`, and `gbnt mount fstab`.

### 21. Transparent Adoption Metrics & Telemetry Privacy (`v2.29.0`)
* **Public Adoption & Download Metrics:** Direct, transparent integration with official GitHub Releases API (`api.github.com/repos/mario-ezquerro/gubernator/releases`) calculating total binary downloads, OS breakdowns (Linux AMD64/ARM64, macOS Apple Silicon/Intel, Windows), release history, stars, and forks.
* **Settings ➔ About & Metrics Dashboard:** Visual KPI cards and platform download badges inside the Settings modal with live refresh capabilities.
* **Zero Cluster Telemetry Guarantee:** Formal 100% on-premise guarantee ensuring no container images, payloads, secrets, database state, application logs, or internal network topology leave the local cluster.
* **Air-Gapped & Privacy Overrides:** Full support for `DO_NOT_TRACK=1` and `GBNT_TELEMETRY=false` to completely disable external release and update checks.
* **Full CLI Parity:** Dedicated CLI flag `gbnt version --metrics` and REST endpoint `GET /api/system/adoption`.

### 22. GlusterFS Multi-Node Cluster Storage Subsystem (`v2.30.0`)
* **3-Way Mirrored Volumes (Replica 3 & Arbiter):** Native distributed volume creation, starting, stopping, and container write-behind cache optimizations (`performance.write-behind`, `flush-behind`, `stat-prefetch`).
* **Trusted Storage Pool Peer Mesh:** Live peer discovery, health probing, latency checks, and quorum diagnostics across Centurion worker hosts.
* **Granaries `/var/contenedores` Auto-Mount:** One-click automated mounting across all cluster nodes directly syncing with Gubernator's `/etc/fstab` management.
* **Self-Healing & Split-Brain Diagnostics:** Real-time heal entry queues, brick health inspection, and manual self-heal triggers.
* **Ansible Automated Provisioning:** Multi-distro automation in `ansible/glusterfs.yml` configuring `glusterfs-server`, firewall ports (`24007`, `24008`, `49152:49251`), brick directories, and default `gv_contenedores` volume.
* **Full CLI Parity:** Dedicated commands for `gbnt gluster status`, `gbnt gluster peer [ls|probe|detach]`, `gbnt gluster volume [ls|create|start|stop|rm|heal]`, and `gbnt gluster mount`.

### 23. Host Disk Monitoring, SLO Alerting & Storage Capacity Dashboarding (`v2.31.0`)
* **Centurion Host Disk Space Telemetry:** Live cluster-wide discovery and metric collection for host root filesystems and container mountpoints (`DiskTotalBytes`, `DiskUsedBytes`, `DiskFreeBytes`, `DiskPercent`) querying Prometheus node-exporter with direct POSIX filesystem stat fallbacks.
* **Overview & Dashboard Storage Cards:** Real-time Cluster Host Storage capacity KPI card and per-node inline disk usage thermometers (color-coded green < 70%, warning amber 70-85%, critical red > 85%) on Overview and Centurions views.
* **Centurions DataTable & Node Details:** Dedicated `HOST DISK (USED / TOTAL)` column and hardware capacity breakdown with free GB indicators and low-space warning badges.
* **Google SRE Sloth SLO Engine Disk Templates:** Native `host-disk` (`Node Disk Capacity < 15%`) and `gluster-storage` (`GlusterFS Cluster Pool`) SLO templates and multi-window burn rate alert rules (`HostDiskFillingFast`, `HostDiskSpaceCritical`).
* **Grafana SRE Dashboard Panels:** Dedicated `Centurions — Host Disk Space Usage %` LCD bar gauge in `gubernator_dashboard.json`.
### 24. Multi-Host Storage Orchestration, GlusterFS Auth & Interactive `/etc/fstab` Subsystem (`v2.32.0`)
* **Multi-Host Remote Orchestration Engine:** Full cluster-wide storage operations enabling actions on **All Hosts** or targeted to **Specific Centurion Nodes** (Manager local execution and Worker automated SSH bridge).
* **GlusterFS & Mount Authentication Fixes:** Resolved session role checks and route bindings for GlusterFS volume lifecycle, `/api/storage/mounts/:id` deletion, and `/etc/fstab` safe synchronization.
* **Interactive Multi-Node `/etc/fstab` Inspector & Editor:** Live configuration browser with Centurion host selection dropdown, monospace syntax editor, automated timestamped backups (`/etc/fstab.bak.<ts>`), and atomic save & apply.
* **Target Node Selection across Storage Suite:** Granular host selection in "Add Network Mount", "Mount All (`mount -a`)", GlusterFS volume creation, and cluster auto-mounting to `/var/contenedores`.
### 25. Docker Named Volumes Discovery, Multi-Node Directory Creator & GlusterFS Persistence Subsystem (`v2.33.0`)
* **Cluster-Wide Docker Named Volumes Discovery:** Live discovery of native Docker volumes (`docker volume ls --format '{{.Name}}\t{{.Driver}}\t{{.Scope}}\t{{.Mountpoint}}'`) across Manager and Worker nodes via local engine and remote SSH execution with volume type and node residency badges.
* **Multi-Node Storage Directory Creator (`mkdir -p`):** Dedicated creation modal and REST API (`POST /api/storage/directories`) supporting path authoring, target Centurion node selection (`All Nodes`, `Manager`, specific workers), and container-optimized POSIX permissions (`0777` / `0755`).
* **Interactive Directory File Explorer (`ls`):** Full-screen directory explorer modal and REST API (`GET /api/storage/directories/ls`) with breadcrumb path navigation, parent directory traversal, live node switching, file/folder metadata inspection, and subfolder creation on any cluster host.
* **Centurion Node Filtering in Volumes View:** Centurion node selector dropdown (`All Centurions`, `Manager`, `Worker 1`, `Worker 2`) and search filter for instant volume isolation by host.
* **GlusterFS Database Auto-Migration & Persistence:** Registered `ManagedGlusterVolume` into central SQLite GORM database migrations, ensuring newly created GlusterFS volumes persist reliably and display across GlusterFS and Mounts dashboards.
* **Clean Network Mount Volfile Parsing:** Sanitized dynamic cluster peer discovery to pass clean IP addresses to `backup-volfile-servers` mount options, eliminating invalid character syntax errors.

### 26. Storage Volumes Centurion Host Residency, Docker Volume Lifecycle & Compose Snippets (`v2.34.0`)
* **Prominent Centurion Host Badges:** Every volume card prominently renders its physical Centurion residency host badge with node icon, role, hostname, and IP (`👑 MANAGER: gbnt-manager (192.168.252.27)`, `💻 CENTURION: gbnt-worker1 (192.168.252.25)`, `🌐 ALL CENTURIONS (Shared Mesh)`).
* **Multi-Node Docker Volume Creator (`docker volume create`):** Dedicated creation modal and REST API (`POST /api/storage/volumes/docker`) supporting custom drivers (`local`, `glusterfs`, `nfs`), driver options, labels, and target Centurion host selection (`All Nodes (Cluster-Wide)`, `Manager`, specific workers).
* **Cluster-Wide Volume Pruning (`docker volume prune -f`):** Dedicated toolbar action and REST API (`POST /api/storage/volumes/docker/prune`) to purge dangling/unused volumes across all cluster nodes or targeted hosts with reclaimed disk space reports.
* **Volume Deletion & Inspection (`docker volume rm / inspect`):** Safe volume deletion modal (`DELETE /api/storage/volumes/docker`) and JSON inspection modal (`GET /api/storage/volumes/docker/inspect`) for Docker volumes.
* **Interactive Docker Compose Blueprint Generator:** One-click "Compose" action generating copyable `docker-compose.yml` service volume binding and external volume blocks for instant integration into Compose Studio.

### 27. GlusterFS Mount Point Sync, Multi-Brick Directory Creator & Host Permissions Subsystem (`v2.35.0`)
* **Automated GlusterFS Mount Point Synchronization:** Proactively bridges GlusterFS distributed volumes into `db.StorageMount` records (`fs_type = 'glusterfs'`), ensuring newly created or existing Gluster volumes instantly register and display across **Network Mounts & /etc/fstab** with live status indicators.
* **Multi-Host Brick Directory Pre-Creation (`mkdir -p`):** Proactive brick filesystem preparation executing `sudo mkdir -p <path> && sudo chmod 0777 <path>` across all target brick hosts (locally on Manager and remotely via automated SSH bridge on Centurion workers) prior to `gluster volume create`.
* **GlusterFS Protocol in Network Mounts Creation Wizard:** Integrated GlusterFS as a first-class storage protocol in the Add Mount dialog with dynamic volume name dropdowns and `localhost:<volName>` device formatting.
* **Direct Mount & Remount Actions in GlusterFS Cards:** Added instant **Mount to fstab / Remount** action buttons and color-coded status badges (`🔗 fstab: /var/contenedores` / `⚠️ Unmounted in fstab`) directly on GlusterFS volume cards.
* **Sudo Elevation for Remote Host Orchestration:** Automated `sudo` privilege elevation across all remote Worker storage operations (`sudo tee -a /etc/fstab`, `sudo sed -i`, `sudo mount -a`, `sudo mkdir -p`).

### 28. Backups & Snapshots Storage Target Picker, Multi-Node Directory Creator & Schedule Engine (`v2.36.0`)
* **Intelligent Storage Target Selector:** Multi-mode selector in Backup and Snapshot creation dialogs enabling one-click selection from discovered Docker Named Volumes, Shared Storage Pools (`/var/contenedores`), Network Mounts, or Stacks, automatically populating paths, volume identifiers, and backup naming blueprints.
* **Inline Multi-Host Directory Creator (`mkdir -p` & `chmod 0777`):** Direct in-modal filesystem preparation action across Manager and Worker nodes (`ApiService.createStorageDirectory`), allowing instant creation of target directories when defining custom backup paths or restore destinations without leaving the dialog.
* **Multi-Target Backup Scheduler (`targetType = 'stack' | 'volume' | 'path'`):** Enriched backup policy scheduler with dedicated selection interfaces for Stacks, Discovered Volumes/Mounts, and Custom Paths, syncing directly into SQLite and background cron runner (`ExecuteScheduledBackup`).
* **Smart Path Auto-Detection & Self-Healing:** Backend source path resolution supporting Docker volume data directories (`/var/lib/docker/volumes/.../_data`), GlusterFS mountpoints, and auto-creation of missing shared storage folders during backup operations.
* **Quick Directory Path Suggestion Chips:** Contextual path chips (`/var/contenedores/`, `/var/lib/docker/volumes/`, `/mnt/shared/`, `/data/`) for rapid path composition.

### 31. Dual-NIC Dedicated Storage Network (GlusterFS), CoreDNS Storage Resolution & Cockpit-Storaged Management Subsystem (`v2.39.0`)
* **Dedicated Dual-NIC Storage Network Architecture (`enp0s2` / `10.10.100.0/24`):**
  - Physical/Virtual NIC isolation separating application, ingress, and management traffic (`enp0s1`: `192.168.252.0/24`) from GlusterFS replication streams, daemons (`24007/24008`), bricks (`49152:49251`), and FUSE mount traffic (`enp0s2`: `10.10.100.0/24`).
  - Automated Multipass and Netplan dual-interface provisioning (`scripts/recreate-cluster-dual-nic.sh`) with persistent routing and peer discovery over `10.10.100.x`.
* **CoreDNS Storage Resolution Subsystem (`*.storage.gbnt.local`):**
  - Integrated CoreDNS storage host resolution dynamically binding `<hostname>.storage.gbnt.local` to each node's dedicated `10.10.100.x` IP address.
  - Automatically updates `gubernator.hosts` in CoreDNS so containers and services can resolve internal storage nodes by domain or IP seamlessly.
* **Live Storage Network Telemetry & Interface Monitor:**
  - Real-time `/proc/net/dev` rate calculation producing per-interface and cluster-wide Rx/Tx throughput (MB/s), packet rates, and link states (`GET /api/storage/gluster/network`).
  - Dedicated Flutter Storage Network dashboard rendering dual-NIC interface cards for all Centurions with live speedometers and traffic distribution badges.
* **Cockpit-Storaged Inspired Management Suite (Total GlusterFS Control):**
  - **Volume I/O Profiling & FOP Breakdown:** Real-time IOPS, read/write speedometers, latency metrics, file operation distribution (LOOKUP, READ, WRITE, STAT, OPENDIR, UNLINK), and block size histogram (`1B-4KB` to `>1MB`) via `gluster volume profile <name> start/info/stop`.
  - **Directory Quotas & Path Limits:** Authoring and enforcing hard disk limits on subdirectories (`gluster volume quota <name> limit-usage <path> <size>`) with consumption progress bars.
  - **Point-in-Time Volume Snapshots & Instant Rollback:** Snapshot creation, description tagging, instant rollback restore (`gluster snapshot restore <name>`), and lifecycle pruning with SQLite persistence (`GET /api/storage/gluster/snapshots`).
  - **Volume Rebalance Engine:** Data migration and brick layout repair (`gluster volume rebalance <name> start/status/stop`).
  - **Container Tuning Options Matrix:** Live configuration and toggling of container-critical Gluster options (`performance.write-behind`, `performance.stat-prefetch`, `performance.quick-read`, `network.ping-timeout`, `cluster.favorite-child-policy`).
* **Sub-Navigation 6-View Dashboard Architecture:**
  - Modern, responsive segmented view selector inside the GlusterFS panel: *Volumes & Peers*, *Performance & I/O (Cockpit)*, *Storage Network (Dual NIC)*, *Quotas & Directory Limits*, *Volume Snapshots*, and *Advanced Tuning Options*.

### 32. Monitoring Dashboards Gauge Consolidation & Centurions Host Thermometers (`v2.39.1`)
* **Consolidated Host Metrics Telemetry:** Removed redundant circular gauges (`Host System Consumption (Gauges)`) in the default Grafana Monitoring dashboard in favor of the unified **Centurions — Termómetros & Estado de Hosts** subsystem.
* **Unified Centurions Visualization:** All host CPU, RAM, Network I/O, and Host Disk space are now represented cleanly via horizontal LCD bargauges and the comprehensive multi-metric Centurions host table starting seamlessly after runtime timeseries panels.

### 33. Automatic Backup & Snapshot Destination Directory Preparation & Self-Healing (`v2.39.2`)
* **Zero-Failure Directory Preparation (`EnsureDirectoryLocal`):** Universal directory preparation engine automatically handling parent filesystem creation, permission elevation (`sudo mkdir -p` and `sudo chmod 0777`), and unprivileged user fallbacks when targeting `/var/backups/gbnt`, `/var/contenedores/backups`, or custom mountpaths.
* **Automatic Recovery & Fallbacks:** If a custom destination directory path is unresolvable or fails creation on restricted filesystems, the backup engine seamlessly creates and uses the user's home backup directory (`~/.gbnt/backups`) without interrupting snapshot execution.
* **Informative UI Notice Banners:** Added dynamic auto-creation guidance banners to both the **Create Compressed Backup / Snapshot** modal and the **Automated Backup Policy Scheduler** informing users that destination folders are prepared automatically with proper permissions upon backup execution.

### 34. Dual-NIC Dedicated Storage Network & GlusterFS Integration across Terraform & Ansible (`v2.39.3`)
* **Multi-Cloud Terraform Storage Network Bridge:** Enhanced Terraform modules across **Hetzner Cloud**, **AWS**, **Proxmox VE**, **Google Cloud Platform (GCP)**, and **DigitalOcean** to configure secondary network interfaces / private storage subnets and export dedicated `storage_ip` attributes directly into `ansible/inventory.ini`.
* **Ansible GlusterFS Dual-NIC Automation (`storage_ip`):** Updated `ansible/glusterfs.yml` and variable templates (`group_vars/all.yml`, `inventory.example.ini`, `inventory.example.yml`) to automatically route peer probing (`gluster peer probe <storage_ip>`), brick topology (`<storage_ip>:<brick>`), and FUSE mount failovers over the dedicated storage network (`10.10.100.0/24` or private VPC).

### 35. GlusterFS Network Security Options & Interactive Configuration Suite (`v2.39.4`)
* **Interactive Network Security & Isolation Subtab:** Redesigned the **GlusterFS Options / Tuning** panel in the Flutter Dashboard into two organized cards: **Storage Network & Security Isolation** (`auth.allow`, `auth.reject`, `network.ping-timeout`, `transport.socket.bind-address`) and **Container Performance & Cache Acceleration** (`performance.write-behind`, `performance.stat-prefetch`, `performance.quick-read`, `cluster.favorite-child-policy`).
* **Dynamic Option Configuration Modal:** Added interactive **Configure / Edit** action buttons on every option tile and a **+ Set Custom Option** header button with quick preset chips (`auth.allow (10.10.100.*)`, `auth.allow (*)`, `network.ping-timeout (10)`, `write-behind (on)`), allowing instant volume option application and defaults reset with automatic UI synchronization.
* **Full CLI Parity (`gbnt gluster volume option`):** Implemented dedicated CLI command `gbnt gluster volume option <volume-name> <key> [value] [--reset]` for configuring and resetting volume tuning and subnet isolation parameters.

### 36. GlusterFS Re-Creation Zero-Error Engine, Network Selector & Interactive Error Inspection (`v2.39.5`)
* **Zero-Error Volume Re-Creation (`brick xattr cleanup`):** Solved GlusterFS volume re-creation errors caused by residual metadata attributes (`trusted.gfid`, `trusted.glusterfs.volume-id`, `trusted.glusterfs.dht`) and `.glusterfs` directory markers from previously deleted volumes by automatically wiping xattrs and syncing permissions across local and remote bricks prior to creation and upon deletion.
* **Storage Network & Subnet Selector in Volume Creator:** Enhanced the **Create GlusterFS Replicated Volume** modal with explicit network routing selection (`🌐 Dedicated Storage Network (Dual-NIC / 10.10.100.0/24)`, `🏢 Management / Primary Network (192.168.x.x)`, `🛠️ Custom Node IPs (Comma-separated)`), enabling flexible interface targeting and multi-IP binding.
* **Detailed Error Inspection Dialog with One-Click Copy:** Replaced fleeting SnackBar notifications with rich, persistent error dialogs containing monospace output inspection, selectable text, and a **Copy Error** button for seamless troubleshooting.

### 37. Auto-Updater Live Progress Tracker & GitHub Release Retry Pipeline (`v2.39.6`)
* **Live Update Progress Screen:** Redesigned the Web UI `UpdateDialog` to remain open during updates with interactive multi-step progress tracking (1. Download release binary from GitHub, 2. Install binary on Manager & Centurion workers, 3. Restart Gubernator cluster daemon, 4. Reconnect and verify updated state) with automatic UI reload upon completion.
* **Release Asset Retry & Backoff Engine:** Implemented 15-attempt (45-second) exponential backoff polling in `updater.go` to handle GitHub Actions build latency when new releases are published, preventing 404 download errors.
* **Safe Binary Replacement & Daemon Restart:** Replaced basic atomic copy with `sudo install -m 755` across `/usr/local/bin/gbnt`, `/app/gbnt`, and active executable paths with automated worker SSH propagation and fallback systemd restart.
### 41. LLM Training & Fine-Tuning Suites on Gubernator (`v2.40.0`)
* **LLaMA-Factory Visual Fine-Tuning Studio (`examples/example-llama-factory`):** Production blueprint for LLaMA-Factory WebUI (`llama-factory.gbnt.local`), enabling no-code/low-code fine-tuning (LoRA, QLoRA, SFT) across Llama-3, Qwen2.5, DeepSeek, and SmolLM models with real-time loss tracking and GGUF quantization.
* **JupyterLab PyTorch LLM Lab (`examples/example-jupyter-llm`):** Interactive AI workspace with PyTorch, Hugging Face `TRL` (SFTTrainer), `PEFT`, `datasets`, and a ready-to-run notebook (`llm_lora_finetuning.ipynb`) with headless script execution (`train_script.py`) targeting cluster shared storage (`/var/contenedores`).
* **Domain Dataset & Distributed Storage Integration:** Seeded Gubernator DevOps Q&A training datasets into distributed shared pools (`/var/contenedores/jupyter-llm` and `/var/contenedores/llama-factory/data`).

### 42. CoreDNS Node-Aware DNS Records & Host-Qualified Scheme (`v2.58.0`)
* **Host-Qualified Service Discovery (`<node>.<service>.gbnt`):** Eliminates multi-node service name collisions by registering node-specific hostnames (`worker-1.caddy.gbnt`, `manager.caddy.gbnt`, `worker-2.web.gbnt`) alongside `.gbnt.local` across all cluster hosts.
* **Full RFC 1123 DNS Label Sanitization:** Automatically converts spaces, parentheses, brackets, underscores, and special characters in stack and task names (`CORE-GBNT (worker-1)` -> `core-gbnt-worker-1`, `[SRE] Monitor (Manager)` -> `sre-monitor-manager`) into strictly compliant DNS domain labels.
* **Multi-Tier Domain Hierarchy & Deduplication:** Generates structured records across 5 addressing levels (Node + Service, Node + Service + Stack, Task ID + Service + Stack, Service + Stack, and Global Service) with atomic record deduplication in `gubernator.hosts`.

### 43. Multi-Source Release Propagation & Instant Version Detection (`v2.58.1`)
* **Multi-Source Detection Cascade (Releases ➔ Tags ➔ Raw Content):** Solved GitHub propagation latency and rate limits by querying GitHub Releases, GitHub Git Tags, and `raw.githubusercontent.com/main/VERSION` concurrently to detect newly pushed versions instantly, even before GitHub Actions finishes compiling assets.
* **Aggressive Cache-Busting & Dynamic TTL:** Added unique query timestamps (`_cb=<nanoseconds>`) and `Cache-Control: no-cache, no-store` headers to bypass GitHub Fastly edge CDN caching, reduced background TTL to 30s, and ensured "Force Re-scan" completely purges in-memory caches.
* **Dynamic Local Version Resolution:** Auto-detects local running version from active runtime binaries and disk `VERSION` files (`/app/VERSION`, `/data/VERSION`, `VERSION`), ensuring accurate SemVer comparison and upgrade notifications across Manager and Workers.

### 44. Streamlined & Minimal CoreDNS Hosts Generator (`v2.58.2`)
* **Zero-Spam Host-Qualified Discovery:** Streamlined `gubernator.hosts` generation to strictly emit clean, canonical `<node>.<service>.gbnt.local` (and `.gbnt`) host-scoped records for system containers, completely eliminating duplicate un-scoped `caddy.gbnt.local` or `loki.gbnt.local` entries across multi-node cluster IPs.
* **Minimalist Stack-Scoped Isolation:** User application containers are mapped strictly to `<service>.<stack>.gbnt.local` and `<node>.<service>.gbnt.local`, reducing total generated DNS entries per container from 28 down to 2-4 pristine records.

### 45. Dynamic & Customizable Enterprise Cluster Base Domain (`v2.59.0`)
* **Enterprise Custom Base Domain (`GBNT_CLUSTER_DOMAIN`):** Replaced hardcoded `gbnt.local` with a fully dynamic cluster domain subsystem configurable via environment variables (`GBNT_CLUSTER_DOMAIN=acme.corp`), persisted centrally in SQLite (`ClusterConfig.ClusterDomain`), and synchronized across all Centurion nodes.
* **Dynamic CoreDNS Zone Generation:** Corefile automatically provisions active DNS zones for `<cluster_domain>` (e.g. `acme.corp`, `internal.banco.es`, `dev.gbnt.local`), serving auto-generated container hostnames `<node>.<service>.<cluster_domain>` and stack records `<service>.<stack>.<cluster_domain>`.
* **Zero-Downtime Hot Domain Updates:** Full REST API (`GET /v1/cluster/domain`, `PUT /v1/cluster/domain`) and Web Dashboard UI management with one-click domain modal in the CoreDNS Management Suite, instantly rewriting Corefile, regenerating `gubernator.hosts`, and reloading CoreDNS via SIGHUP.

























