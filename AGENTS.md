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

### 46. Compose Studio Persistent Selection & Infallible Hardware Key Engine (`v2.59.3`)
* **Zero-Lag In-Memory Selection Preservation:** Real-time recording of `_lastSelectedText` and `_lastSelection` in memory without triggering widget rebuilds (`setState`), preserving the exact highlighted text block even when clicking toolbar buttons or when the editor loses focus.
* **Direct Hardware & Focus Key Interception (`FocusNode.onKeyEvent`):** Intercepts keyboard shortcuts (`Ctrl+C`, `Cmd+C`, `Ctrl+V`, `Cmd+V`, `Ctrl+X`, `Cmd+X`, `Ctrl+A`, `Cmd+A`) at the root `FocusNode` level before Flutter's `EditableText` consumes or cancels them.
* **Multi-Layer Cross-Origin Clipboard Bridge:** Synchronous DOM textarea execution with zero visibility artifacts, Flutter `Clipboard.setData()`, and `navigator.clipboard.writeText()` guarantees 100% clipboard write success across both HTTP self-hosted IPs and HTTPS domains.
* **Instant Action Feedback:** Dynamic SnackBar notifications showing exact char count and preview snippet of copied selection vs full document.

### 47. Native Browser Clipboard Event Interception & macOS Cmd+C/Ctrl+C Engine (`v2.59.7`)
* **Native Browser DOM Copy/Cut Event Interception:** Bypasses Flutter Web's internal `TextInputPlugin` by intercepting native browser `copy` and `cut` events in DOM capture phase (`addEventListener('copy', ..., true)`).
* **HTTP-Compliant Clipboard Data Injection:** Injects highlighted text directly via `event.clipboardData.setData('text/plain', text)` during standard `Cmd+C` / `Ctrl+C` gestures, functioning reliably on HTTP without HTTPS or browser permission restrictions.
* **Custom Context Menu & Selection Retention:** Prevents default browser right-click context menu from clearing text selection, displaying a specialized Flutter popup menu with copy/paste actions.
* **Synchronous DOM Fallbacks for Toolbar Actions:** Guarantees clipboard parity whether invoked via keyboard shortcuts, custom right-click menu, or toolbar buttons.

### 48. Universal Toolbar & Full Document Clipboard Copy Engine (`v2.59.8`)
* **Infallible Direct Clipboard Injection in `copySync`:** Implements dynamic capture-phase one-time `copy` event listening within `ClipboardService.copySync`, forcing `e.clipboardData.setData('text/plain', text)` on any programmatic copy action (such as "Copy All YAML", "Copy Node ID", "Copy Task ID", and "Copy Logs").
* **Programmatic vs Keystroke Copy Segregation:** Filtered native `copy`/`cut` event handlers in Compose Studio and Compose Editor to ignore `TextAreaElement`/`InputElement` targets, preventing programmatic document copies from being overridden by keyboard selection hooks.
* **100% Reliable Cross-Browser HTTP Clipboard Parity:** Fixes silent copy failures for toolbar buttons across macOS Safari, Chrome, and Firefox on self-hosted HTTP endpoints without SSL requirements.

### 49. Image Security & SBOM Navigation Bar Aesthetics & Pill Indicator Polish (`v2.59.9`)
* **Refined Sub-Tab Pill Indicator:** Replaced cramped, unpadded `Tab(icon: Row(...))` buttons with generous `Tab(height: 42, child: Padding(...))` widgets and `indicatorSize: TabBarIndicatorSize.tab`.
* **Elevated Ambient Glow & Geometry:** Styled the selected orange tab indicator with an 8px border radius, 4px inset container margins, and an ambient drop shadow (`BoxShadow(color: Color(0xFFF97316).withValues(alpha: 0.35), blurRadius: 8, offset: Offset(0, 2))`).
* **Enhanced Typography & Contrast:** Configured bold white text with letter-spacing for active tab state and high-contrast muted text for unselected tabs.

### 50. Stable Sidebar Navigation & Dynamic Item Index Parity (`v2.59.10`)
* **Eliminated Intermittent Sidebar Item Flashing:** Removed legacy hardcoded `i >= 7 && i <= 9 && !widget.monitorRunning` item hiding in `sidebar.dart` that caused Caddy Ingress, CoreDNS, and Monitoring to intermittently appear/disappear on state polling.
* **Persistent Navigation Hierarchy:** Guaranteed stable 1:1 index matching across all 16 sidebar navigation entries regardless of SRE monitor container states.
* **Clean Section Visual Dividers:** Added a sleek, permanent divider separating Core Services from Observability Suites (Monitoring, Loki Logs, Network Monitor, Jaeger, Scope).

### 51. Self-Healing Watchdog & Automated Container Restart Subsystem (`v2.59.11`)
* **Universal `--restart unless-stopped` Policy:** Injected native container restart policies into `docker.StartContainer` and remote worker SSH dispatchers, ensuring containers auto-recover across host reboots and dockerd restarts.
* **Manager Self-Healing Watchdog Daemon:** Implemented background reconciliation loop (`StartSelfHealingWatchdog`) continuously auditing stack replica health, detecting dead or missing containers, and automatically re-scheduling replacements to the least-loaded healthy nodes.
* **Worker Execution Health Monitor:** Added active container state verification in `gbnt legion join` worker loops to detect exited or crashed processes and attempt local restarts before escalating to the Manager.

### 52. Non-Blocking Prometheus Telemetry Engine & Live Status Parity (`v2.59.12`)
* **Asynchronous Telemetry Snapshot Cache:** Eliminated synchronous, multi-second CLI commands (`gluster volume heal <vol> info`) from Prometheus's `Collect()` loop, replacing them with a non-blocking in-memory snapshot cache.
* **Sub-Millisecond `/metrics` Scrapes:** Reduced Prometheus scrape response time from 15+ seconds down to <1ms, resolving context deadline timeouts.
* **100% Up Gubernator Status in Grafana:** Restored `up{job="gubernator"} = 1` across Prometheus and Grafana dashboards for permanent, green "Gubernator Status: UP" display.

### 53. CPU & RAM Resource Constraints & Compose Studio Copilot (`v2.59.13`)
* **Comprehensive Examples Review & Resource Bounds:** Injected explicit `deploy.resources.limits` (max CPU & RAM) and `deploy.resources.reservations` (guaranteed min CPU & RAM) across all 18 production blueprints and example stacks (Kubeflow, N8N, JupyterLab, LLaMA-Factory, WordPress, Jaeger, SLO services, and Single-Node Manager).
* **Dedicated Resources Copilot Tab:** Added a new **Resources** tab in Compose Studio and Compose Editor dialogs featuring 5 one-click production presets (Micro Service, Web/API App, Database/Cache, Data Science/ML, and AI/LLM GPU Model).
* **Interactive Custom Resources Builder:** Integrated visual form controls with live core/RAM dropdown pickers and instant YAML snippet generation directly into the editor at correct indentation.

### 54. Containers Telemetry & Resource Limits Display (`v2.59.14`)
* **Universal "Containers" Terminology Standardization:** Renamed all user-facing instances of "Tasks" / "tacks" to "Containers" across sidebar navigation, breadcrumbs, overview stat cards, Legions stacks tables, and dialog titles.
* **CPU & Memory Columns in Containers Table:** Integrated visual `CPU` (limits & reservations) and `MEMORY` badges with color-coded chips into the PlutoGrid Containers dashboard and CLI (`gbnt container ls` / `gbnt task ls`).
* **Docker Engine & Worker Dispatch Resource Bounds:** Forwarded `--cpus`, `--memory`, and `--memory-reservation` to local Docker containers and remote Centurion SSH dispatches with dynamic backend Compose fallback resolution.

### 55. Live Container CPU & Memory Consumption Telemetry (`v2.59.15`)
* **Real-Time cAdvisor Container Telemetry:** Added `PopulateContainerMetrics()` to query Prometheus cAdvisor metrics (`container_cpu_usage_seconds_total` and `container_memory_working_set_bytes`) and populate `CpuPercent` and `MemUsedBytes` across all cluster tasks.
* **PlutoGrid Combined Usage / Limit Visualization:** Enhanced Containers table columns `CPU (USAGE / LIMIT)` and `MEMORY (USAGE / LIMIT)` with color-coded live metrics (`3.5%`, `414.0 MB`) paired with underlying limit definitions (`Limit: 1.0 Core`, `Limit: 4G`).
* **CLI Live Metrics Parity:** Updated `gbnt container ls` / `gbnt task ls` to display live consumption alongside resource limits in the terminal table.

### 56. Universal FlexString YAML Resource Parsing & Dynamic CPU/RAM Extraction (`v2.59.16`)
* **Flexible YAML Resource Parsing (`FlexString`):** Implemented custom YAML unmarshaler capable of reading CPU bounds expressed as numeric literals (`cpus: 1.0`, `cpus: 2`), strings (`cpus: "1.0"`), or legacy Compose v2 keys (`mem_limit`, `mem_reservation`, `cpus`).
* **Dynamic Compose Resource Bounds Resolution:** Upgraded backend backfill in `stateHandler` to parse both `deploy.resources` and service-level fields from any raw Compose file, propagating explicit CPU and Memory limits to active tasks and containers.

### 57. Multi-Node Container Termination, Stack Redeploy Purge & Kubeflow 4/4 Health (`v2.59.17`)
* **Remote SSH Task Termination (`StopTaskOnNode`):** Upgraded `StopTaskOnNode` and `StopStackContainers` to dispatch remote SSH commands (`sudo docker rm -f <container>`) to remote worker Centurions, completely eliminating orphaned containers and port binding collisions (`Bind for 0.0.0.0:9000 failed`).
* **Atomic Stack Redeployment Purge:** Enhanced `StackDeployHandler` to atomically stop all remote containers, remove old tasks, and prune stale services before deploying updated compose stacks, maintaining clean 4/4 replica ratios in Legions dashboard.

### 58. Automated Stack Deduplication & Dead Orphan Task Auto-Pruning (`v2.59.18`)
* **Automated Stack Deduplication in State Sync:** Integrated automatic deduplication of stack records with identical names in `stateHandler`, preserving only the latest active stack and cleaning up superseded services and tasks.
* **Dead Orphan Task Garbage Collection:** Added auto-pruning for dead tasks whose parent services or stacks were previously destroyed, guaranteeing accurate `4/4` container counts on the Legions dashboard.

### 59. Interactive Stack-to-Containers Filtered Navigation & Deep Linking (`v2.59.19`)
* **Interactive Stack & Badge Click Navigation:** Made stack names and container count badges across **Legions [Stacks]** table and **Overview** ("Recent Legions") interactive `InkWell` elements with tooltips, arrow indicators, and primary hover styling.
* **Auto-Filtered Containers View (`initialFilterStack`):** Clicking on any stack name immediately switches the active dashboard tab to **Containers** (`TasksPage`) and auto-applies the stack filter into PlutoGrid and search bar, isolating precisely the containers belonging to that stack.

### 60. Stack Name Search Predicate Matching & Streamlined Container Filtering (`v2.59.20`)
* **Stack Name Search Predicate Integration:** Fixed `TasksPage` filter predicate to inspect parent `stack.name` and `stack.id` in `_getPlutoRows`, ensuring that searching or clicking a stack name (`kubeflow-stack`) immediately matches all underlying services and containers.
* **Seamless Double-Filter Conflict Resolution:** Streamlined PlutoGrid row population and search synchronization so deep-linked stack filters display all matching containers reliably.

### 61. Universal Centurion Onboarding Suite & Live Terminal Console (`v2.60.0`)
* **3-Tab Universal Onboarding Suite (`AddNodeDialog`):** Completely redesigned the Centurion worker onboarding experience with 3 specialized workflows:
  * ⚡ **Quick Join (Copy & Paste):** Instant 1-click command cards for **One-Liner Automated Installer** (`curl -fsSL .../join.sh | sudo bash -s ...`), **Docker Container** (`sudo docker run ... legion join`), and **Gubernator CLI Binary** (`sudo gbnt legion join`), allowing workers behind NAT/firewalls or cloud VMs to join without SSH keys or password configuration.
  * 🚀 **Remote SSH Provisioning + Live Terminal Console:** Manager connects via SSH supporting 3 distinct authentication modes: **Password**, **Custom Private Key (.pem / RSA / ED25519)**, and **Manager Public Key Auto-Discovery** with an interactive monospace Linux console streaming step-by-step progress (`SSH Handshake`, `Hardware Discovery`, `Docker Engine Check`, `Agent Deployment`, `System Stacks`, `Aqueducts & Telemetry`).
  * ☁️ **Cloud-Init & Automation (IaC):** Ready-to-copy `cloud-config` YAML blueprint for automated first-boot provisioning on Proxmox VE, OpenStack, AWS EC2 UserData, GCP, Hetzner Cloud, and Terraform.
* **New Cluster Endpoints (`/api/node/join-info` & `/api/node/join.sh`):** Added native REST APIs returning auto-detected Manager IP, join tokens, API tokens, Manager SSH public key, pre-rendered join commands, and standalone bootstrap shell script with public `/join.sh` alias.
### 62. Image Security Auto-Remediation, Risk Warnings & Safe Automated Rollback Subsystem (`v2.61.0`)
* **Proactive DevSecOps Auto-Remediation Engine (`internal/security/remediation.go`):** Added intelligent version candidate recommendation heuristics suggesting safe security patches (same major version, Alpine minimal variant, e.g. `postgres:13.18-alpine`, `redis:7.4-alpine`, `nginx:1.27-alpine`) versus modern stable releases, calculating operational risk levels (`low`, `medium`, `high`).
* **Safe Automated Rollback Protection:** Automated remediation captures a cryptographic backup snapshot of the previous Compose definition prior to redeployment; if the upgraded container crashes or fails healthchecks within 20s, the engine automatically rolls back to the previous Compose state with zero downtime.
* **Interactive Risk & Impact Warning Dialog (`ImageRemediationDialog`):** Material Design 3 modal displaying affected stacks/services, version candidate radio selection, breaking changes and data migration warnings, safe auto-rollback toggle, direct "Open in Compose Studio" link, and a live Linux monospace execution console streaming progress logs (`Backup Compose`, `Image Patch`, `Database Update`, `Service Redeploy`, `Health Probe`, `Auto-Rollback`, `Security Re-Scan`).
* **REST APIs & CLI Parity:** Added `GET /api/security/remediate/preview?image=<name>`, `POST /api/security/remediate`, and dedicated CLI command `gbnt image fix <image> [--to <tag>] [--stack <id>] [--auto-rollback]`.

### 63. Stack In-Use Validation & Stale Scan Purging Subsystem (`v2.61.2`)
* **In-Use Stack Relationship Heuristics:** Validates image usage across active `db.Service` records and raw Compose file definitions (`db.Stack.RawComposeFile`) to accurately distinguish in-use images from stale/orphaned container images.
* **Orphan Warnings & Scan Purge:** Highlights orphaned scan reports with warning badges and adds `🗑️ Purge Stale Scan` and `🧹 Prune Orphans` bulk purge actions in the UI, REST API (`DELETE /api/security/scans/:id`, `POST /api/security/scans/prune-orphans`), and CLI (`gbnt scan prune`, `gbnt scan rm`).

### 64. Docker Host Image Lifecycle, Layer Inspector & The Imperial Forge (`v2.62.0`)
* **Cluster-Wide Physical Docker Image Management:** Real-time discovery of images stored across Manager and Centurion worker nodes via local Docker CLI and remote SSH bridge, reporting repository tags, physical disk footprints (MB/GB), creation dates, and container utilization.
* **Cluster Host Image Pruning (`docker image prune -a -f`):** One-click cluster disk reclamation removing unused and dangling container images across all hosts, calculating and displaying exact reclaimed disk space.
* **Image Construction & Layer History Inspector (`docker history`):** Chronological layer visualization with instruction breakdowns (`FROM`, `RUN`, `ENV`, `COPY`, `EXPOSE`, `ENTRYPOINT`, `WORKDIR`), layer byte sizes, and reverse-engineered `Dockerfile` generation with 1-click clipboard export and "Edit & Rebuild in Forge" bridge.
* **The Imperial Forge (Image Build Studio):** In-browser Dockerfile IDE with built-in production blueprints (Alpine Minimal Hardened, Go Multi-stage, Node.js Runtime, Python FastAPI), multi-node Centurion build targeting, build arguments (`ARG`), `--no-cache`, and real-time streaming compilation terminal.

### 65. Streamlined In-Cluster Image Signing, Keypair Persistence & Gatekeeper Security Labels (`v2.62.1`)
* **In-Cluster ECDSA Keypair Persistence:** Stores generated ECDSA P-256 private keys securely inside the cluster database, completely eliminating manual copying and pasting of raw PEM keys for signing operations.
* **Interactive SignImageDialog & Quick Sign Actions:** Redesigned signing modal featuring a searchable cluster image dropdown, in-cluster keypair selector with status pills, automatic Docker SHA-256 RepoDigest discovery, and 1-click `🔏 Sign` buttons directly on every image card.
* **Compose Studio Zero-Trust Autocomplete & Security Labels:** Added comprehensive autocomplete snippets and Gubernator Copilot cards for `gbnt.security.require-signature=true`, `gbnt.security.max-cve-severity=critical`, `gbnt.security.allow-unfixed-cve=false`, and `gbnt.security.signer="Cluster Administrator"`.

### 66. Multi-Host Image & Signature Distribution, Signed Registry & Cluster Admission Subsystem (`v2.63.0`)
* **Multi-Host Container Image Distribution (`docker save` ➔ SSH ➔ `docker load`):** Internal cluster bridge streaming locally built or signed container images across Manager and Centurion worker nodes, eliminating the prerequisite of an external Docker registry.
* **Cluster-Wide Synchronized Signature Admission:** Centralized validation ensures that images signed on the Manager or via in-cluster keys are verified across all Centurion nodes, enabling any node in the cluster to execute signed tasks seamlessly.
* **Signed Images & Distributed Registry UI:** Dedicated catalog view in the Signatures tab highlighting all signed cluster images, signer identities, cryptographic digests (`sha256:...`), and physical host presence.
* **Interactive Distribution Dialog (`ImageDistributeDialog`):** Material Design 3 modal with target Centurion node selection (`All Centurions`, specific worker), live streaming SSH progress, and execution results breakdown.
* **Full CLI Parity:** Added dedicated command `gbnt image distribute <image> [--node all|node-id]` and REST API endpoint `POST /v1/images/distribute`.

### 67. Cryptographic Signature Revocation & Unsign Subsystem (`v2.63.1`)
* **Signature Revocation Engine (`RevokeImageSignature`):** Resets signature verification state (`signature_status = 'unsigned'`, removes signer identity and timestamp) across SQLite scan records, immediately enforcing Gatekeeper admission blocks on deprecated or compromised images.
* **Interactive Revocation Modals & UI Actions:** Added direct `🔏❌ Unsign` action buttons in the Signed Images Registry and a confirmation dialog preventing accidental revocation. Scan card popup menus now include `Revoke Signature (Unsign)` alongside orphan deletion options.
* **Full CLI & REST API Parity:** Added dedicated command `gbnt image unsign <image>` and REST API endpoints `POST /v1/security/unsign` and `POST /api/security/unsign`.

### 68. Master Server Stacks & Built-in POC Blueprints Subsystem (`v2.64.0`)
* **Master Server Filesystem Stack Loading (`~/.gbnt/stacks/`):** Enables loading and deploying Docker Compose `.yml` files stored directly on the Master/Manager server disk without requiring client workstation file uploads. Automatically discovers and indexes files in `~/.gbnt/stacks/`, `~/.gbnt/examples/`, `/etc/gubernator/stacks/`, and custom server directories.
* **Embedded Production POC Examples Library (`internal/examples/`):** 8 production-grade Compose blueprints embedded directly into the Go binary (`hello-loadbalancer`, `wordpress-mysql`, `public-https`, `sloth-slo`, `n8n-workflow`, `jaeger-tracing`, `jupyter-datascience`, `sre-observability`). Automatically exports to `~/.gbnt/examples/` on startup.
* **Cluster Installation Bootstrap Auto-Deployment:** Deploy all POC blueprints automatically when initializing a new cluster via CLI (`gbnt legion init --with-examples`) or environment variable (`GBNT_DEPLOY_EXAMPLES=true gbnt serve`).
* **Interactive Web UI Suite:**
  - `ServerStackPickerDialog`: Split-view dialog for browsing server directories, searching files, viewing YAML syntax preview, and 1-click loading into editor or direct deployment.
  - `POCExamplesDialog`: Production blueprints catalog with category filters, tags, descriptions, services badges, 1-click "Deploy POC", 1-click "Studio" editor bridge, "Deploy All POCs" bulk runner, and an in-platform Master Server deployment guide.
  - Seamlessly integrated into `NewStackDialog`, `ComposeStudioPage`, and `LegionsPage` headers alongside workstation PC upload.
* **Full CLI & REST API Parity:** Added `gbnt examples ls`, `gbnt examples deploy <id|all> [--target-node]`, `gbnt stack server-ls [--dir]`, `gbnt stack deploy --from-server <path>`, and REST APIs (`GET /v1/examples`, `POST /v1/examples/deploy`, `GET /v1/stack/server-files`, `POST /v1/stack/server-deploy`).

### 69. Stacks Categorization, Base vs Deployed Grouping & Dynamic Stop/Start Subsystem (`v2.65.0`)
* **Base vs Deployed Stacks Grouping Heuristics:** Automatically separates infrastructure foundation stacks (`CORE-GBNT` / CoreDNS + Caddy, `[SRE] Monitor` / Prometheus + Grafana + Loki + Jaeger) from user-deployed application stacks across the dashboard and API.
* **Interactive Group Segmented Buttons & Visual Badges:** Added a 3-way segmented filter (`All`, `🚀 Deployed Apps`, `🏛️ Base Stacks`) and prominent visual badges (`[BASE]` with purple foundation icon, `[APP]` with blue rocket icon) in the stacks table and overview card.
* **Dynamic Stop / Start Compose Lifecycle:**
  - When active, stacks render an amber **Stop** action button (`Icons.stop_circle_outlined`) with confirmation protection; stopping halts all running containers across Manager and Worker nodes (`docker stop` or remote SSH execution) while preserving the stack configuration and volume state.
  - When stopped, the button dynamically transforms into an emerald **Start** action button (`Icons.play_circle_filled`); starting resumes the stopped containers (`docker start`) or schedules fresh tasks directly from the saved Compose definition (`stack.RawComposeFile`).
  - Container column visualizes live state (`Running: X/Y` with green play indicator vs `Stopped: 0/Y` with amber stop indicator).
* **Full CLI & REST API Parity:** Added CLI commands `gbnt stack stop <stack_id>` and `gbnt stack start <stack_id>` along with REST API endpoints `POST /api/stack/:id/stop`, `POST /api/stack/:id/start`, `POST /v1/stack/:id/stop`, and `POST /v1/stack/:id/start`.

### 70. Stack Task Reconciliation, Desired Replicas Invariant & Orphan Pruning Subsystem (`v2.66.0`)
* **Strict Desired Replicas Invariant:** Enforces that total tasks tracked for any service never exceed `svc.DesiredReplicas` (e.g. 2 containers for a 2-service WordPress + MariaDB stack), eliminating container accumulation caused by unpurged dead instances during self-healing restarts.
* **Active Host Docker Inspection & Health Auditing:** The Watchdog engine now directly inspects local Docker container states (`InspectContainerStatus`) and remote Centurion worker tasks. If a container exits or dies, it is immediately flagged, its container is safely removed (`docker rm -f`), and a replacement task is scheduled.
* **Smart Stack Stop & Start Lifecycle Reconciliation:**
  - When stopping a stack, exactly `DesiredReplicas` newest containers are placed into `stopped` state; any excess or dead tasks are purged from the DB and their physical containers removed from the host.
  - When starting a stopped stack, any surplus tasks beyond `DesiredReplicas` are pruned before containers resume, guaranteeing the stack never launches with lingering dead containers.
* **Cluster-Wide Orphan Container Garbage Collector:** `PruneOrphanContainers` scans the host Docker daemon for unrecognized `gbnt-*` containers (skipping system containers like `gbnt-coredns`, `gbnt-caddy`, `gbnt-monitor-*`) and removes them.
* **Interactive UI Reconciliation & Prune Controls:**
  - Header action: "Reconcile & Prune" button (`Icons.cleaning_services_outlined`) in `LegionsPage` for one-click cluster-wide reconciliation and dead container purging.
  - Per-stack action: "Reconcile Stack" button (`Icons.auto_fix_high`) in `LegionsPage` and `DashboardScreen` to immediately reconcile and prune any specific stack.
  - Automatic reconciliation on state queries (`/api/state`) ensures the dashboard always displays accurate, normalized container counts.
* **Full CLI & REST API Parity:** Added CLI commands `gbnt stack reconcile [stack_id]` and `gbnt task prune` along with REST endpoints `POST /api/stack/:id/reconcile`, `POST /api/tasks/prune`, `POST /v1/stack/:id/reconcile`, and `POST /v1/tasks/prune`.

### 71. Compose Studio Resizable Split, Responsive Smart Wizard & Architecture Block Navigator (`v2.67.0`)
* **Interactive Resizable Vertical Split Divider:**
  - Added a draggable vertical split handle with `SystemMouseCursors.resizeColumn` between the YAML editor and the Gubernator Copilot panel.
  - Dynamically resizes the Smart Wizard panel width between `320px` and `920px`, with double-click toggling between standard (`460px`) and wide (`680px`).
  - Added quick width preset buttons (`460px`, `680px`) directly in the Copilot header.
* **Adaptive Responsive Smart Wizard Tab Bar:**
  - Replaced the horizontal clipping row with an adaptive `Wrap` container featuring themed pill buttons (`Docker`, `Resources`, `Caddy`, `SLO`, `Security`, `Nodes`, `Storage`, `Templates`).
  - All 8 categories cleanly flow and fit into 1 or 2 rows based on the panel width, completely eliminating horizontal scrolling and truncated options.
  - Each tab pill features a signature accent color (Sky, Emerald, Purple, Amber, Rose, Teal, Orange, Gold) and a live status dot (`●`) indicating whether that architectural block is already configured in the current Compose YAML.
* **Compose Architecture Blocks Navigator & Visual YAML Markers:**
  - **Real-Time YAML Block Parser (`_detectComposeBlocks`)**: Automatically scans the Compose document and detects all 7 architectural blocks with their line numbers (`startLine` - `endLine`) and summaries.
  - **Blocks Navigator Bar**: Positioned directly above the code editor, displaying color-coded chips for each block (`🐳 Docker Core: L3-L12`, `⚡ Resources: L16-L23`, `🌐 Caddy Ingress: L25-L28`, `📈 Sloth SLO: L30-L33`, `💾 Storage: L35-L38`).
  - **1-Click Jump & Copilot Sync**: Clicking any block chip instantly scrolls and positions the cursor at that block's line in the YAML editor, simultaneously opening the corresponding category in the Smart Wizard.
  - **Dashed `+ Block` Quick-Add Chips**: Any unconfigured blocks are shown with a dashed outline; clicking one immediately opens the Smart Wizard tab with 1-click production blueprints ready to insert.
  - **Architecture Block Gutter Strip**: A vertical marker strip beside the CodeField displaying colored block pins matching line positions, toggleable via the editor action bar (`Icons.view_sidebar_outlined`).

### 72. Compose Studio Non-Deploying Save Stack & Draft Mode Subsystem (`v2.68.0`)
* **Strict Separation of Save vs Deploy in Compose Studio:**
  - Fixed a critical regression where clicking "Save Stack" (`_saveCompose`) when authoring a new stack invoked `ApiService.deployStack`, causing unexpected immediate container launches and scheduling.
  - "Save Stack" is now strictly decoupled from deployment, operating in pure **Draft / Definition Mode**. It persists the stack and service definitions in the SQLite database and exports to `~/.gbnt/stacks/<name>.yml` on the Master host without creating or scheduling Docker tasks.
  - Deployment is reserved exclusively for the "Deploy Stack" / "Save & Redeploy" button (`_saveAndDeploy`).
* **Cluster-Wide Stack Save API (`POST /api/stack/save` & `POST /v1/stack/save`):**
  - Added dedicated endpoints (`saveStackHandler` in `internal/web/server.go` and `StackSaveHandler` / `SaveStackRaw` in `internal/api/stack.go`).
  - Automatically validates YAML syntax, extracts stack name, creates or updates `db.Stack` (`raw_compose_file`), registers `db.Service` specifications (replicas, limits, constraints, ports, volumes, environment), and writes the YAML archive to `~/.gbnt/stacks/<name>.yml`.
  - Guarantees zero tasks (`db.Task`) or Docker containers are scheduled on any cluster node during save operations.
* **Smart UI State Transition & Informative Feedback:**
  - Upon saving a new stack, Compose Studio smoothly transitions `_selectedStackId` to the newly generated stack UUID without leaving the editor.
  - Toolbar buttons display clear contextual tooltips:
    - "Save Stack": *"Save stack definition (Draft mode: does NOT start containers)"*
    - "Deploy Stack" / "Save & Redeploy": *"Deploy stack and start all containers on cluster nodes"*
  - Informative floating SnackBar notifications clearly inform the user: *"Stack <name> saved successfully (Draft mode: containers not deployed)"*.

### 73. Compose Studio Smart YAML Merger & Deduplication Subsystem (`v2.69.0`)
* **Context-Aware In-Place Updates for Singletons (Unique Blocks):**
  - Solved snippet duplication and YAML bloat when clicking wizard options, copilot presets, or autocompletion chips multiple times.
  - Distinctly recognizes and handles singleton configuration blocks:
    - **Resource Limits & Reservations (`deploy.resources`):** Replacing limits (e.g. switching between Micro, Web, DB, ML, or AI presets, or updating via the Custom Resources Builder) modifies the existing `resources:` block in-place with exact indentation, never generating duplicate `deploy:` or duplicate `resources:` blocks.
    - **Container Restart Policy (`restart:`):** Replaces the restart policy line in-place (e.g. from `unless-stopped` to `always`) rather than appending multiple contradictory `restart:` declarations.
    - **Container Healthcheck Probes (`healthcheck:`):** Replaces existing healthcheck probes in-place without duplicating test parameters or intervals.
    - **Placement Constraints Affinity (`deploy.placement.constraints`):** Replaces conflicting single-target constraints (such as `node.role == worker` vs `node.role == manager`, or switching pinned centurions `node.hostname == nodeA` to `node.hostname == nodeB`) in-place while allowing complementary constraints (e.g. role + GPU + hostname) to coexist under a unified `constraints:` block.
    - **Unique Service Labels (`labels:`):** Replaces matching label keys (such as `ingress.host`, `gbnt.caddy.port`, `gbnt.slo.*`, `gbnt.security.*`) in-place when new values are selected.
* **Intelligent Deduplication for Multi-Item Collections:**
  - Enables multiple distinct entries for collections (`volumes:`, `ports:`, `environment:`) while strictly enforcing deduplication:
    - **Volumes (`volumes:`):** Appends new host/container mounts or shared storage pools (`/var/contenedores/...`) to the existing `volumes:` list. If the exact mount is already present, avoids duplicating lines and warns the user.
    - **Ports (`ports:`):** Appends newly selected port bindings under existing `ports:` list, skipping duplicate port mappings.
    - **Environment (`environment:`):** Updates existing environment variable keys in-place (e.g. `NODE_ENV=production`) while cleanly appending new keys under the existing `environment:` block.
* **Universal Smart Insertion Engine (`ComposeSmartMerger`):**
  - Integrated across all Compose Studio entrypoints:
    - Dedicated Smart Copilot side panel tabs (Resources, Docker, Caddy, SLO, Security, Nodes, Storage).
    - Custom Resources Builder with reactive Max Limits and Min Reservations dropdowns.
    - Autocomplete Interactive Suggestion Bar chips (`ComposeSuggestionBar`).
    - Quick Snippets dropdown and Embedded Compose Editor Dialog (`ComposeEditorDialog`).
* **Instant Visual Feedback & Comprehensive Unit Test Suite:**
  - Color-coded floating SnackBars provide immediate confirmation of the action taken:
    - 🔄 **Updated In-Place (Cyan):** Configuration updated without duplicating YAML sections.
    - ➕ **Added to Existing (Green):** New distinct entry appended to existing collection.
    - ℹ️ **Already Configured (Amber):** Identical configuration already present in Compose definition.
    - 📋 **Configured / Inserted (Blue):** New section cleanly created with proper YAML hierarchy.
  - 100% test coverage with automated unit tests in `web-ui/test/compose_smart_merger_test.dart` validating singleton replacement, collection deduplication, and syntax preservation.











































