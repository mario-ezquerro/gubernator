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

### 74. Compose Studio Client Workstation "Save on Disk" Subsystem (`v2.69.1`)
* **Local Workstation File Export ("Save on Disk"):**
  - Added dedicated client file export allowing engineers to directly save / download active Compose YAML configurations onto their local workstation computer.
  - Automatically sanitizes the filename using the stack name (`<stack-name>.yml`), with fallback to `docker-compose.yml`.
  - Seamlessly creates an in-memory YAML blob (`application/x-yaml`) and triggers browser-native download without requiring round-trips to the remote manager.
* **Dual Action Access across Compose Studio:**
  - **Top Header Toolbar**: Positioned alongside "Open PC" (`_importFile`) for an intuitive local file management workflow (`Open PC` ➔ Edit with Copilot ➔ `Save on Disk`).
  - **YAML Editor Action Bar**: Directly accessible in the editor quick action bar next to Copy and Paste for rapid developer workflows.
  - **Advanced Compose Editor Dialog (`ComposeEditorDialog`)**: Header icon button enabling instant disk downloads directly from the modal view.
* **Informative Visual Feedback:**
  - Displays instant floating notification: `✓ Saved "<filename>" to local computer disk` with green confirmation icon.

### 75. Compose Studio Responsive Header & Toolbar Restructuring (`v2.69.2`)
* **Elimination of Title Overlap & Collision:**
  - Enclosed the Compose Studio header title and subtitle column within an `Expanded` widget with `TextOverflow.ellipsis` and `maxLines: 1`.
  - Guaranteed that the subtitle ("Author, edit, validate, and deploy...") can never push against, collide with, or slip underneath the "Create New Stack" dropdown regardless of viewport width.
* **Balanced Two-Tier Toolbar Architecture:**
  - **Top Primary Header Bar**: Dedicated exclusively to cluster lifecycle actions:
    - Left: Studio Title, icon, and `IDE & COPILOT` badge.
    - Right: Stack Selector Dropdown (`✨ Create New Stack` / active stack), `Reset` button, `Save Stack` (Draft mode), and primary `Deploy Stack` / `Save & Redeploy` button.
  - **Secondary Action Toolbar**: Fully scrollable horizontally (`SingleChildScrollView(scrollDirection: Axis.horizontal)`) housing all configuration and file operations:
    - Stack Name field (220px) and Target Placement Node dropdown (280px).
    - Vertical visual divider.
    - Workstation file tools: `Open PC` (upload) and `Save on Disk` (download).
    - Remote cluster filesystem tool: `Master Server` (`~/.gbnt/stacks/`).
    - Vertical visual divider.
    - Blueprints & Snippets: `Templates` blueprint dropdown and `POC Blueprints` catalog.
* **100% Overflow Immunity:**
  - Zero `RenderFlex` overflow errors on laptops, split-screen windows, or tablets.

### 76. Atomic Stack-Level Scheduling & Host Load Balancing (`v2.70.0`)
* **Single-Host Atomic Stack Deployment:**
  - Standard Docker Compose stacks rely inherently on intra-host container networking (`<stack>_default` bridge), local inter-service DNS resolution (`web` reaching `db:3306`), and local shared volume mounts.
  - Gubernator schedules the entire Compose stack as an **atomic deployment unit** onto a single chosen Centurion host node. All services and containers of that stack are placed and managed together on that host.
* **Cluster-Wide Stack Load Balancing:**
  - What Gubernator balances across the cluster Centurions are the **Stacks themselves**, rather than scattering individual containers of the same stack across separate machines.
  - `SelectOptimalNodeForStack(constraints, targetNode)` counts active stacks on each healthy candidate node (`db.DB.Model(&db.Stack{}).Where("node_id = ?", n.ID).Count(&stackCount)`), with active task count as secondary tie-breaker.
  - Prioritizes healthy Worker nodes over Manager (Workers first, Manager as fallback or if explicitly constrained).
* **Atomic Stack Migration & Eviction (`MigrateStack`):**
  - Moving a stack (`POST /v1/stack/:id/migrate` and `POST /api/stack/:id/migrate`) relocates all containers belonging to that stack together to the destination Centurion, cleaning up on the previous node and starting them on the new host.
  - Node draining (`drainNodeTasks`) discovers all stacks hosted on the draining node and migrates each stack atomically to an active replacement Centurion.
* **Watchdog Self-Healing & Host Affinity:**
  - Reconciler repairs (`reconcileStackInternal`) strictly schedule replacement replicas onto `stack.NodeID`, preserving co-location with sibling containers. If the assigned node is dead/unreachable, the watchdog fails over the entire stack to another active worker.
* **Web Dashboard Host Residency Badges:**
  - Stacks (Legions) DataTable in `legions_page.dart` and `dashboard_screen.dart` features a dedicated **`HOST NODE`** column.
  - Renders a color-coded Centurion badge (icon, hostname, IP, and role: amber for `MANAGER`, sky blue for `WORKER`) with one-click access to the stack migration dialog.

### 77. Remote Worker Container Actions & Terminal Dispatch (`v2.70.1`)
* **Multi-Node Container Inspect Resolution:**
  - `taskInspectHandler` (`GET /api/task/:id/inspect`) dynamically detects if a container is hosted on a remote Centurion worker.
  - Automatically queries the container over SSH (`sudo docker inspect <name>`) and streams raw JSON back to the Web Dashboard, resolving `exit status 1` / `no such object` errors on multi-node clusters.
* **Remote Container Interactive Shell (PTY over SSH & WebSockets):**
  - `taskShellHandler` (`GET /api/task/:id/shell`) connects the browser xterm.js terminal directly to containers running on remote Centurion workers.
  - Spawns an interactive PTY session over SSH (`ssh -tt ... sudo docker exec -it <name> /bin/sh`), bridging bidirectional WebSocket frames without requiring local Docker daemon residency.
* **Clean Remote Container Logs Streaming:**
  - `taskLogsHandler` (`GET /api/task/:id/logs`) incorporates `-o LogLevel=ERROR` and resolves host identity across both node IDs and network IPs.
  - Eliminates SSH host key warning banners from container logs output.
* **Cluster-Aware Container Lifecycle & Deletion:**
  - `deleteTaskHandler` and `stopContainerByName` invoke `docker.RemoveContainerOnNode(task.NodeID, task.ContainerName)`, properly terminating and pruning containers on the remote host where they physically run.

### 78. SRE Worker Daemon Disambiguation & Network Topology Base Classification (`v2.70.2`)
* **Strict 3-Container SRE Worker Monitoring:**
  - SRE monitoring on Centurion worker nodes is strictly composed of 3 daemons: `cAdvisor` (`gbnt-monitor-cadvisor`), `Node Exporter` (`gbnt-monitor-node-exporter`), and `Promtail` (`gbnt-monitor-promtail`).
  - Removed redundant Weave Scope probe deployment from `EnsureWorkerMonitoring`. Scope is decoupled and managed strictly as part of Network Topology.
* **Worker Task Executor Canonical Container Discovery:**
  - Added `ContainerName` field decoding to the worker task executor in `internal/cli/legion.go`.
  - Worker healthchecks now inspect canonical container names (`gbnt-monitor-promtail`, `cadvisor`, `node-exporter`) instead of defaulting to `gbnt-<taskID>`. This prevents false `dead` reports and eliminates the creation of duplicate Promtail containers on workers.
  - In `SyncWorkerSreStacks` (`internal/monitor/register.go`), automatically purges any rogue or duplicate tasks and containers across worker SRE services.
  - Updated `startLocalExecutor` in `internal/api/executor.go` to strictly skip system infrastructure stacks (`isSystemStack(svc.StackID)`), preventing duplicate SSH container dispatch.
* **Network Topology Classified as BASE Infrastructure:**
  - Updated `_isBaseStack` in `web-ui/lib/screens/pages/legions_page.dart` and `web-ui/lib/screens/dashboard_screen.dart` to recognize `[SUPER] Net-Topology` (`super-net-topology-mgr`, `super-scope-stack-*`, `topology`, `scope`, `[super]`).
  - Network Topology stacks now display the purple **`BASE`** badge with `Icons.foundation`, are categorized under Base infrastructure, and are protected against user app actions (duplicate, host migration).
  - Updated `isSystemStack` in `internal/api/node_crud.go` and `internal/api/watchdog.go` to safeguard topology stacks from watchdog reconciliation and node drain migrations.

### 79. Full UI & Backend BASE Classification for Network Topology Stacks & Containers (`v2.70.3`)
* **Explicit `[BASE] Net-Topology` Stack Naming:**
  - Standardized stack naming in `internal/monitor/register.go` to `[BASE] Net-Topology (Manager)` and `[BASE] Net-Topology (<nodeID>)` on workers.
  - Automatically migrates existing database stack records from `[SUPER]` to `[BASE]`.
  - Added automatic Scope stack synchronization to `RegisterInDB` whenever Scope is running on node boot or SRE refresh.
* **Containers Table BASE Badges & Cohort Segmented Filters:**
  - Enhanced `TasksPage` (`web-ui/lib/screens/pages/tasks_page.dart`) with top segmented button controls: `All`, `Deployed Apps`, and `Base Containers` with dynamic item counts.
  - Integrated `_isBaseTask` classifier identifying Core, SRE, and Network Topology containers (`gbnt-monitor-scope`, `gbnt-monitor-scope-probe`).
  - Added purple `BASE` and blue `APP` badges directly in the `STACK` column of the PlutoGrid container table.
  - Bound dynamic `ValueKey` to PlutoGrid to ensure instant, reactive filtering upon segmented button toggle.
* **Worker Agent Healthcheck & Reconnection Resilience:**
  - Worker loop in `internal/cli/legion.go` checks container runtime status locally via `docker inspect` before reporting `dead`, immediately updating alive containers to `running`.
  - Re-authenticated workers using `--token` and `--manager` flags with current cluster join token.
  - Added cache-busting query parameter (`flutter_bootstrap.js?v=2.70.3`) to prevent stale browser assets.

### 80. Multi-Host Docker Image Deletion & Lifecycle Management (`v2.70.4`)
* **Dedicated "Delete Image" Button across Security Views:**
  - Added red outlined **`Delete`** button (`Icons.delete_forever`) directly on every image card in **Vulnerabilities & Scans** (`_buildVulnerabilitiesTab`) next to `View CVEs`.
  - Added **`Delete Image`** button in the **SBOM Explorer** header toolbar (`_buildSBOMTab`) next to `SPDX JSON`.
  - Added **`Delete`** button on all signed and unsigned image cards in **Signatures & Cluster Registry** (`_buildSignaturesTab`).
* **Interactive Target Host & Purge Dialog:**
  - Upgraded `_deleteHostImage` in `web-ui/lib/screens/pages/image_security_page.dart` into an interactive Material 3 dialog.
  - Allows selecting target hosts: `All Cluster Hosts (Cluster-wide)` or specific Centurion nodes (`Manager`, `gbnt-worker1`, etc.).
  - Includes options for forced removal (`-f / --force`) and purging scan & SBOM metadata from the cluster database.
  - Displays explicit warning regarding physical storage reclamation (`docker rmi`).
* **Database Scan Purging on Image Removal:**
  - Enhanced `ImageHostDeleteHandler` (`DELETE /v1/images/host-delete`) and `imageHostDeleteHandler` (`DELETE /api/images/host-delete`) with `purge_db` parameter.
  - Automatically cascades image deletion to SQLite `image_scans` and `image_vulnerabilities` tables when `purge_db=true`, ensuring UI tables stay clean and in sync.

### 81. Elimination of Image Auto-Resurrection & Optimistic Removal (`v2.70.5`)
* **Decoupled Read Operations from Auto-Scanning:**
  - Refactored `ListScans` and `GetSecuritySummary` in `internal/security/scanner.go` into pure read operations directly querying SQLite.
  - Eliminated automatic `AutoSyncClusterImages()` scan triggers during `GET /api/security/scans`, preventing deleted images from being automatically re-scanned and resurrected upon dashboard refresh.
* **Cascading Subquery Purging in Database:**
  - Fixed database deletion in `internal/security/scanner.go`, `internal/web/server.go`, and `internal/api/image_lifecycle_handlers.go` to properly delete from `image_vulnerabilities` using subquery on `scan_id` (since `image_vulnerabilities` references scans rather than storing `image_name`).
  - Added clean removal of associated `image_sboms` and `image_scans`.
* **Active Workload Warning & Optimistic UI Removal:**
  - Enhanced `_deleteHostImage` in `web-ui/lib/screens/pages/image_security_page.dart` to detect active workloads and display a warning explaining that deleting an in-use image untags it on hosts while leaving running containers operational until their stack is updated.
  - Added immediate optimistic removal from `_scans` upon successful deletion, guaranteeing the image vanishes immediately from the table without delay.

### 82. SRE Observability Architecture Profiles & Presets Subsystem (`v2.71.0`)
* **Pluggable Observability Architecture Profiles:** Modular SRE monitoring presets tailored to cluster capacity and hardware constraints:
  - ⚡ `ultra-light` (*VictoriaMetrics + VictoriaLogs + Fluent Bit*): Designed for 1-5 Centurions and <30 containers on budget VPS (2-4GB) and edge with <500MB RAM consumption.
  - 🌟 `cloud-native` (*Prometheus + Loki + Promtail + Grafana + Sloth*): Recommended default for 3-15 Centurions and 20-100 containers with built-in SLO error budget calculation.
  - 🚀 `unified-otel` (*ClickHouse + OpenTelemetry Collector + SigNoz*): Next-gen unified columnar storage for microservices with heavy distributed tracing.
  - 🏢 `enterprise-elk` (*OpenSearch / ELK + Fluent Bit + Metricbeat*): Enterprise full-text search, audit logging, and SIEM compliance for 10+ Centurions and >100 containers.
  - 🌐 `external-saas` (*Vector / Fluent Bit Forwarder*): Zero-footprint forwarding directly to Datadog, Splunk, or Grafana Cloud with <100MB RAM usage.
* **Interactive Web UI Profile Selector (`SreProfilesDialog`):** Accessible via "SRE Stack Profiles" in the Monitoring toolbar, rendering rich cards with sizing chips (Hosts, Containers, RAM), ideal environment callouts, component breakdowns, and one-click stack switching.
* **Full CLI Parity (`gbnt monitor profiles` & `switch`):** Dedicated commands `gbnt monitor profiles`, `gbnt monitor switch <id>`, and `gbnt monitor init --profile=<id>` with formatted tabular sizing summaries.
### 83. Advanced Production POC Blueprints, Documentation & Server Directory Navigation (`v2.72.0`)
* **6 New Production POC Architectures & Complete Documentation:**
  - 🧠 `deepseek-vllm` (*DeepSeek & vLLM High-Throughput Inference Engine*): OpenAI-compatible LLM inference server running DeepSeek R1 with vLLM PagedAttention, GPU hardware targeting, and Open-WebUI chat frontend.
  - 🔍 `pgvector-rag` (*GenAI RAG Search & Vector Database Stack*): Production RAG pipeline featuring PostgreSQL 16 with pgvector extension, Qdrant vector database, and Open-WebUI knowledge base search.
  - 📊 `kafka-clickhouse` (*Real-Time Data Streaming & Big Data Analytics*): Event-driven data pipeline combining Apache Kafka (KRaft mode - no ZooKeeper), ClickHouse columnar OLAP database, and Kafka-UI web console.
  - 🔨 `gitea-woodpecker` (*Private GitOps Forge & Container CI/CD Suite*): Lightweight self-hosted DevOps stack: Gitea source control + Woodpecker CI server and distributed worker runners placed on Centurion workers.
  - ⚡ `valkey-sentinel` (*High-Availability In-Memory Cache & Sentinel Cluster*): Fault-tolerant distributed caching stack using Valkey 7.2 (Linux Foundation Redis) with master-replica replication and quorum Sentinel failover.
  - 🔑 `keycloak-sso` (*Enterprise Identity & Single Sign-On Suite*): Enterprise IAM with Keycloak 24 and PostgreSQL, providing OAuth2/OIDC federation and direct integration with Gubernator LDAP/AD security.
* **Expanded POC Library Catalog (16 Total Blueprints):** Fully registered in `internal/examples/examples.go` with embedded compose YAML definitions in `internal/examples/data/` and comprehensive `README.md` guides in `examples/`.
* **Interactive Master Server Filesystem Navigation (`ServerStackPickerDialog`):**
  - Enhanced server directory browsing with quick location shortcuts (`~/.gbnt/examples`, `~/.gbnt/stacks`, `/var/contenedores`, `/etc/gubernator/stacks`, `~`).
  - Interactive breadcrumb navigation trail with parent directory traversal (`[⬆]`).
  - Navigable subdirectories list allowing users to explore nested folder structures across the master server.
### 84. GlusterFS Multi-Node Granular Selection, Topology Validation & Auto-Tuning (`v2.73.0`)
* **Granular Centurion Node Multi-Selection in GlusterFS Modal:**
  - Upgraded `_showCreateGlusterVolumeDialog` in `web-ui/lib/screens/pages/storage_page.dart` with interactive host checkboxes for every Centurion in the cluster.
  - Quick-selection chips: *All Nodes*, *3 Nodes (R3)*, and *2 Nodes (R2)* for instantaneous topology configuration.
  - Automatically targets selected physical hosts and maps node IDs, host IPs, and dedicated dual-NIC storage interfaces (`10.10.100.0/24`).
* **Live GlusterFS Topology Divisibility Validation:**
  - Dynamic mathematical validator verifying that `total_selected_nodes % replica_count == 0` in real time before executing volume creation.
  - Color-coded status feedback:
    - ✅ **Green Success Banner:** Confirms topology validity with subvolume breakdown (e.g. `3 bricks ÷ Replica 3 = 1 subvolume`, or `4 bricks ÷ Replica 2 = 2 subvolumes`).
    - ⚠️ **Amber Warning Banner:** Blocks submission when selection is incompatible (e.g. 4 nodes with Replica 3), detailing exact node adjustment recommendations or suggested replica switches.
* **Auto-Tuning & Multi-Host Mount Orchestration (`gluster.go` & `remote.go`):**
  - Backend `CreateGlusterVolume` auto-tunes replica multiplier when unconstrained (automatically configuring 4 nodes into distributed-replicated $2 \times 2$ pools).
  - Explicit pre-flight validation preventing opaque Gluster CLI crashes with actionable error messages.
  - Enhanced `GetTargetHostIPs` in `internal/storage/remote.go` to support comma-separated target node lists, enabling targeted automated `/etc/fstab` mounting across specified subsets of cluster nodes.

### 85. Multi-Host Docker Daemon (/etc/docker/daemon.json) Management Subsystem (`v2.74.0`)
* **Centralized Cluster-Wide Docker Engine Orchestration:**
  - Complete control and synchronization of `/etc/docker/daemon.json` across all hosts in the cluster with automatic syntax pre-validation and timestamped backups (`/etc/docker/daemon.json.bak.<ts>`).
  - Supports zero-downtime hot reloading via `systemctl reload docker` (SIGHUP) alongside `systemctl restart docker` and offline save-only options.
* **Flexible Targeting Scope:**
  - 🌐 **All Centurions:** Broadcasts and applies daemon configurations cluster-wide.
  - ⚡ **GPU Nodes Only:** Dynamically targets Centurions with GPU hardware labels (`gbnt.node.gpu=nvidia`, `gpu=true`, `cuda`) or auto-detected NVIDIA hardware.
  - 👑 **Manager Only:** Isolates changes strictly to the Gubernator manager host.
  - 💻 **Specific Centurion:** Granular targeting to any individual cluster node.
* **1-Click Production Presets & Blueprints:**
  - 🌟 `Producción Recomendada`: Container log rotation (`json-file`, `max-size: 20m`, `max-file: 3`), `live-restore: true` (zero container downtime on reload/restart), `storage-driver: overlay2`, DNS `1.1.1.1, 8.8.8.8`, and concurrency optimizations (`max-concurrent-downloads: 10`).
  - 🚀 `Nodo IA & GPU NVIDIA`: Production blueprint + native `nvidia-container-runtime` integration and default GPU runtime activation for AI, LLM, vLLM, and PyTorch workloads.
  - 📈 `Prometheus & SRE Observability`: Production blueprint + native Docker Prometheus telemetry exporter on `:9323` with experimental flags.
  - 🧹 `Mínimo / Limpio`: Streamlined baseline with log rotation and live-restore.
* **Modern Web Dashboard Dialog (`DockerDaemonDialog`):**
  - Accessible via "Docker Config" header button on Centurions view and per-node context menu.
  - 7 categorized tabs: *Logs & Cero Paradas*, *Redes & DNS*, *Registros & Espejos*, *GPU & Runtimes*, *Métricas & Almacenamiento*, *Editor JSON Raw* (with live syntax checking and formatter), and *Estado en Clúster* (real-time node daemon badges and one-click host config inspector).
* **Full CLI Parity (`gbnt node daemon`):**
  - `gbnt node daemon inspect [--scope=all|gpu|manager|node] [--node=<id>]`
  - `gbnt node daemon apply [--scope=...] [--node=...] [--preset=production|gpu|sre|minimal] [--file=<path>] [--action=apply_and_reload|apply_and_restart|save_only]`

### 86. Multi-Host Service Placement, Anti-Affinity & Dynamic Caddy Load Balancing Subsystem (`v2.75.0`)
* **Multi-Host Service Placement & Anti-Affinity Spread (`internal/api/stack.go`):**
  - Upgraded stack scheduling engine to evaluate placement constraints and spread strategies per service rather than enforcing single-host atomic co-location for all workloads.
  - Detects multi-host intent via `spread: node.id` in `deploy.placement.preferences`, `gbnt.placement.strategy=spread` in service labels, multi-replica services with Caddy load balancing, or distinct service-level placement constraints.
  - Anti-affinity algorithm sequentially distributes replicas of the same service across distinct physical Centurion nodes before assigning secondary replicas to least-loaded nodes.
* **Specialized Hardware Affinity & Node Pinning:**
  - Independent placement of compute/AI services to GPU nodes (`gbnt.node.gpu == nvidia`) while keeping stateful databases pinned to specific hosts (`node.hostname == ...`) and web APIs across general workers (`node.role == worker`).
* **Dynamic Caddy Multi-Upstream Load Balancing (`internal/aqueducts/ingress.go`):**
  - Automatically queries all live, running container instances across all Centurions for each `ingress.host` and emits a dynamic multi-upstream Caddyfile reverse proxy block.
  - Configurable load balancing algorithms via labels: `gbnt.caddy.lb` (`round_robin`, `least_conn`, `ip_hash`, `first`, `random`).
  - Active upstream healthcheck probes with automatic failover via `gbnt.caddy.health_uri` (e.g. `/health`), `gbnt.caddy.health_interval` (default `5s`), and `gbnt.caddy.health_timeout` (default `2s`).
* **Dedicated Compose Studio & Copilot Suite:**
  - Upgraded Copilot tab to **"Placement & LB"** (cyan hub icon) with 1-click anti-affinity snippets, Caddy load balancing policy presets (Round Robin, Least Conn, IP Hash), active health probe cards, and hardware affinity chips.
  - Smart autocompletion chips for `placement.spread`, `gbnt.placement.strategy`, `gbnt.caddy.lb`, and `gbnt.caddy.health_uri`.
  - Added new starter blueprint: **"Multi-Host Load Balanced Web"** in the Compose Studio template library.

### 87. Node Metadata Injection, CI Caddyfile Resilience & Multi-Host Server Echo Examples (`v2.75.1`)
* **Automated Node Metadata Environment Injection (`internal/api/tasks.go`, `internal/api/executor.go`):**
  - Containers deployed on any Centurion worker or manager automatically receive cluster node context: `GBNT_NODE_ID`, `GBNT_NODE_IP`, `GBNT_NODE_ROLE`, `GBNT_TASK_ID`, and `GBNT_SERVICE_NAME`.
  - Enables web apps, microservices, and metrics collectors to natively identify which physical machine and task instance is processing requests without requiring manual compose boilerplate.
* **CI & Headless Caddyfile Resilience (`internal/aqueducts/ingress.go`):**
  - Hardened `GenerateCaddyfile()` with automated `os.MkdirAll(filepath.Dir(caddyfilePath), 0755)` ensuring headless runners (such as GitHub Actions) and fresh node boots write reverse proxy configs reliably without directory missing errors.
* **Multi-Host Server Echo & WhoAmI Examples (`examples/example-loadbalancer/`):**
  - Added `02-multi-host-affinity.yml`: an interactive Python 3 Alpine dashboard displaying physical Centurion node ID, node IP, container ID, and unique node color badges (Green for Worker 1, Blue for Worker 2, Purple for Worker 3) with live 2-second auto-refresh and `/health` probes.
  - Added `03-whoami-affinity.yml`: standard `traefik/whoami` anti-affinity deployment with least-connections load balancing.
### 88. Built-in POC Blueprints Hardening & Multi-Architecture Modernization (`v2.75.2`)
* **Stack Lookup by ID or Name Across All Lifecycle Handlers (`internal/api/stack_crud.go`):**
  - Upgraded `StackServicesHandler`, `StackRmHandler`, `StackStopHandler`, `StackStartHandler`, and `StackReconcileHandler` to locate stacks by `id = ? OR name = ?`.
  - Enables engineers and automated scripts to manage stacks by human-readable name (`gbnt stack rm gitea-woodpecker`, `gbnt stack stop deepseek-vllm`) seamlessly without requiring GUID lookups.
* **Woodpecker CI v3 Migration & Image Lifecycle Hardening (`gitea-woodpecker`):**
  - Replaced deprecated `:latest` tags with production SemVer `:v3` for `woodpeckerci/woodpecker-server` and `woodpeckerci/woodpecker-agent`.
  - Eliminates fatal crash loops (exit code 30) caused by upstream Woodpecker image tag deprecation policies.
* **Storage Mount Permission Pre-allocation (`internal/docker/engine.go`):**
  - Enhanced `StartContainer` to automatically pre-create host bind-mount target directories under `/var/contenedores/...` with `0777` POSIX permissions before invoking Docker run.
  - Guarantees non-root container workloads (Gitea UID 1000, Woodpecker Server UID 10000, PostgreSQL, Valkey) have write access to shared persistent storage without permission denied errors.
* **CoreDNS Cluster-Wide Inter-Service Aliases (`internal/aqueducts/dns.go`):**
  - In `GenerateHostsFile()`, non-system user application stacks now automatically register bare `<service>`, `<service>.<stack>`, and `<service>.<domain>` records pointing to target container/node IPs.
  - Provides frictionless inter-service networking (e.g. `woodpecker-agent` reaching `woodpecker-server` or `woodpecker-server.gitea-woodpecker.gbnt.local`).
* **Worker Node Container Cluster DNS Injection (`internal/cli/legion.go`, `internal/docker/engine.go`):**
  - Workers automatically inherit manager IP via `GBNT_DNS_SERVER` and `GBNT_MANAGER_IP` upon `gbnt legion join`.
  - Automatically injects `--dns <manager_ip>` into containers running on Centurion workers, bridging worker tasks directly to cluster-wide CoreDNS resolution across all nodes.
* **Keycloak IAM & Multi-Node Database Networking (`keycloak-sso`):**
  - Resolved `ERROR: Failed to obtain JDBC connection: keycloak-db` by integrating `hosts /etc/coredns/gubernator.hosts` into CoreDNS root `.` fallback zone block in `DefaultCorefile()`, ensuring single-label hostnames (`keycloak-db`, `postgres`, `gitea`) resolve directly via CoreDNS before falling back to public DNS forwarders.
  - Added `--dns <manager_ip>` and `--dns-search gbnt.local` to `executeRemoteTask` in `internal/api/executor.go` and `StartContainer` in `internal/docker/engine.go`, ensuring all containers on workers can resolve inter-service names cluster-wide.
  - Added automatic remote volume directory pre-creation (`mkdir -p && chmod 777`) via SSH in `internal/api/executor.go` before container start, preventing storage permission errors on worker hosts.
  - Added automatic post-start CoreDNS hosts and Caddy ingress regeneration (`GenerateHostsFile()` / `GenerateCaddyfile()`) when remote worker tasks reach `running` state in `executor.go`, ensuring Caddy Ingress immediately provisions reverse proxy routes (`auth.gbnt.local`, `ci.devops.gbnt.local`, etc.) instead of showing the default fallback page.
  - Cleaned up misplaced `ingress.host` and `gbnt.caddy.port` under `placement.constraints` in `examples/example-keycloak-sso/docker-compose.yml` and `internal/examples/data/keycloak-sso.yml`.
* **DeepSeek Universal Multi-Arch Support & GPU Segregation (`deepseek-vllm`):**
  - Replaced the monolithic 16GB CUDA-only x86_64 vLLM image in the default blueprint with **Ollama** (`ollama/ollama:latest`), enabling fast, lightweight (~1.5GB) deployment across Apple Silicon (ARM64), Linux AMD64/ARM64, and CPU-only testing environments.
  - Provided dedicated `docker-compose-vllm-gpu.yml` for datacenter NVIDIA GPU servers with strict hardware affinity constraints (`gbnt.node.gpu == nvidia`) to prevent GPU workloads from exhausting CPU worker node storage.
  - Comprehensive architectural and operational documentation in `examples/example-deepseek-vllm/README.md`, `examples/example-gitea-woodpecker/README.md`, and `examples/example-keycloak-sso/README.md`.

### 89. Port Collision Detection, Disk-Pressure Aware Scheduling & CI Verification Hardening (`v2.76.0`)
* **Docker Compose Host Port Collision Detection Subsystem (`internal/api/stack.go`, `internal/web/server.go`):**
  - Added real-time published host port extraction and collision analysis (`DetectPortConflicts`) inspecting incoming compose files against all active tasks across target nodes and the cluster.
  - Detects intra-compose collisions (multiple services in the same file claiming the same host port) and inter-stack collisions with running workloads.
  - Returns structured HTTP 409 Conflict with detailed collision metadata: conflicting host port, protocol, service name, occupying stack name, occupying service, host node ID/IP, and suggested next free available port.
  - Added `--auto-remap-ports` flag to `gbnt stack deploy` and Web Dashboard API: automatically rewrites conflicting host ports in the Compose YAML string to suggested free ports before scheduling.
  - Added `--force` override flag to bypass collision verification when intentional port-sharing is desired.
  - CLI renders an actionable, formatted diagnostic table indicating the exact service, port, colliding stack/service, node IP, and suggested port adjustments with remediation commands.
* **Disk-Pressure Aware Cluster Scheduling Engine (`internal/api/stack.go`, `internal/web/server.go`):**
  - Integrated `monitor.PopulateNodeMetrics(allNodes)` directly into `SelectOptimalNodeForStack`.
  - Added intelligent `NodeDiskPressure` avoidance: nodes with critical disk utilization (`DiskPercent >= 90%` or `DiskFreeBytes < 1GB`) are automatically deprioritized during stack placement, preventing container pull failures (`no space left on device`).
* **GenAI RAG Search & Vector Database Blueprint Hardening (`example-pgvector-rag`):**
  - Decoupled published host ports to eliminate collisions with other standard blueprints (`postgres-vector` mapped to `5433:5432`, `rag-ui` mapped to `8082:8080`).
  - Added `QDRANT_URI=http://qdrant.rag.gbnt.local:6333` required by modern Open-WebUI multi-tenancy vector engines.
  - Aligned `gbnt.caddy.port` labels (`5433` and `8082`) with host publish mappings, guaranteeing Caddy reverse-proxy connectivity with 200 OK across cluster nodes.
  - Verified live multi-node deployment with Qdrant vector database API (`http://qdrant.rag.gbnt.local`) and Open-WebUI (`http://search.rag.gbnt.local`).
* **CI Race Condition & SQLite Table Isolation Fix (`internal/api/api_test.go`):**
  - Resolved `no such table: tasks / nodes` flakiness in `TestAtomicStackSchedulingAndBalancing` by decoupling published test ports (`8081:80` and `8082:80`), enforcing test mutex isolation, and verifying clean test teardown.
  - Verified 100% green passing test suite with `go test -v -race ./...` and zero `go vet` static analysis warnings.

### 90. Web UI Interactive Port Collision Resolution Suite (`v2.76.1`)
* **Interactive Port Conflict Diagnostic Dialog (`web-ui/lib/widgets/port_conflict_dialog.dart`):**
  - Designed modern Material 3 diagnostic modal that intercepts HTTP 409 Conflict responses on stack deployments.
  - Displays formatted conflict cards for each port collision with service name, conflicting host port and protocol badge, occupying stack name, conflicting service name, Centurion node ID & IP, and suggested next available free port.
  - Actionable resolution options:
    - ⚡ **Auto-Remap Ports**: Automatically rewrites conflicting host ports in Compose YAML to suggested free ports and continues deployment with zero downtime or manual YAML authoring.
    - ⚠️ **Force Deploy**: Overrides collision detection and forces deployment on requested host ports.
    - ❌ **Cancel**: Aborts deployment cleanly without mutating cluster state.
* **Unified Frontend Integration across Stacks & Studio:**
  - **Compose Studio (`compose_studio_page.dart`):** Deploying directly from the web IDE triggers the interactive conflict resolver; selecting Auto-Remap dynamically updates the YAML code editor with the new ports and redeploys smoothly.
  - **Legions / Stacks Dashboard (`legions_page.dart`):** Integrated into New Stack modal, Server Stack Picker, and POC Blueprint one-click deployments.
  - **Overview & Dashboard (`dashboard_screen.dart`):** Integrated into Duplicate Stack and top-level stack authoring dialogs.
* **Frontend Data Models & Client API (`web-ui/lib/models/models.dart`, `web-ui/lib/services/api_service.dart`):**
  - Added `PortConflictModel` and `DeployStackResult` data contracts.
  - Added `ApiService.deployStackDetailed` supporting `autoRemapPorts` and `force` flags with structured conflict decoding.
  - Updated backend endpoint to return remapped YAML content in responses for live UI synchronization.

### 91. Enterprise OIDC & OAuth2 Single Sign-On (SSO) Subsystem (`v2.77.0`)
* **Multi-Provider SSO Authentication:** Native OpenID Connect (OIDC) and OAuth2 authentication supporting Google Cloud, GitHub, GitLab, Keycloak, Azure AD / Microsoft Entra, and custom generic identity providers.
* **PKCE & Cryptographic State Security:** High-security Authorization Code Grant with Proof Key for Code Exchange (PKCE SHA-256) and randomized state tokens protecting against replay and authorization code interception attacks.
* **Auto-Provisioning & RBAC Claims Mapping:** Automatic user profile provisioning with token signature verification, dynamic email extraction, and role assignment (`admin`, `operator`, `readonly`).
* **Web UI SSO Integration:** Seamless dual-mode authentication in Flutter Web login dialog with instant OAuth redirects, provider preset templates, and administrative provider management in Settings.

### 92. eBPF Kernel Network Observability, Socket Probing & Live Service Mesh Subsystem (`v2.78.0`)
* **Dual-Engine Architecture (Native Linux eBPF + Resilient Emulation):**
  - High-performance non-invasive observability inspecting Linux tracefs (`/sys/kernel/tracing`, `/sys/kernel/debug/tracing`), BPF filesystem (`/sys/fs/bpf`), and socket filters without requiring CGO or external clang toolchains.
  - Built-in resilient kernel emulation and socket correlate engine for macOS, Windows, and unprivileged container environments ensuring 100% development and testing parity.
* **L4/L7 Protocol Decoding & Socket Correlation:**
  - Correlates kernel socket tables (`/proc/net/tcp`, `/proc/net/tcp6`, `/proc/net/udp`, `/proc/net/udp6`) and interface statistics (`/proc/net/dev`) with Docker containers and Gubernator task metadata.
  - Decodes protocols (HTTP, gRPC, DNS, TCP, UDP, Redis, Postgres), calculating round-trip time (RTT latency ms), throughput (Bps), retransmits, and dropped packets.
* **Real-Time Streaming & REST API:**
  - Manager REST API (Port 4000) and Web API (Port 4001): `GET /v1/ebpf/stats`, `GET /v1/ebpf/flows`, `GET /v1/ebpf/topology`, `POST /v1/ebpf/simulate`, and Server-Sent Events (SSE) `GET /v1/ebpf/stream`.
* **Flutter Web Dashboard — eBPF Live Hub (`web-ui/lib/screens/pages/ebpf_page.dart`):**
  - **Live Captured Flows Stream:** Real-time auto-refreshing data table with protocol filters, health/error status chips, search query, RTT thermometers, throughput rates, and modal flow inspector.
  - **Service Mesh Topology View:** Visual interactive service mesh graph showing connected services, directional arrows, throughput MB/s, RTT latency, and error rates.
  - **Kernel Probes & Diagnostics:** Kernel version telemetry, active attach points list (`kprobe/tcp_v4_connect`, `tracepoint/sock_sendmsg`, etc.), protocol distribution charts, interface packet counters, and on-demand traffic simulator.
* **Full CLI Parity (`gbnt ebpf ...`):**
  - Dedicated CLI commands for `gbnt ebpf status`, `gbnt ebpf flows`, `gbnt ebpf topology`, and `gbnt ebpf simulate`.

### 93. eBPF Animated Vector Mesh Canvas & Jaeger Distributed Tracing Subsystem (`v2.79.0`)
* **Interactive 2D Vector Mesh Canvas (`web-ui/lib/widgets/ebpf_animated_mesh_canvas.dart`):**
  - High-performance 2D vector canvas rendering draggable service blocks with real-time health, protocol badges, throughput rates, and flow counters.
  - Directional Bézier curves with arrows ($\rightarrow$) indicating exact traffic flow direction between containers, services, ingress, and data layers.
  - Dynamic animated travelling data particles/comets moving along vectors at frequencies and velocities proportional to kernel eBPF throughput ($B/s$, $KB/s$, $MB/s$).
  - Protocol-coded aesthetics: HTTP (Blue), gRPC (Purple), DNS (Teal/Green), Redis/Databases (Orange), and Faults/Errors (Pulsing Red).
* **Dual Topology View Modes in eBPF Live Hub (`web-ui/lib/screens/pages/ebpf_page.dart`):**
  - Seamless segmented switcher allowing users to toggle between **2D Vector Graph** (interactive animated canvas) and **Edges Table** (tabular matrix with RTT latency, throughput, and error rates).
* **Deep Jaeger Distributed Tracing Integration:**
  - Cryptographic 128-bit `trace_id` correlation on every eBPF flow and communication edge.
  - Direct deep links to Jaeger UI (`http://<host>:16686/trace/<trace_id>`) from the Vector Canvas Inspector, the Edges Table, and the Flow Details modal for instant root-cause and span waterfall analysis.

### 94. Declarative Autoscaling Subsystem & GPU/CPU Hardware Affinity (`v2.80.0`)
* **Declarative Compose Autoscaling Engine (`internal/autoscaler/`):**
  - Horizontal pod and container autoscaling configured entirely via Compose labels (`gbnt.autoscaling.*`).
  - Automatic evaluation every 15 seconds within Gubernator's self-healing watchdog loop.
  - Multi-metric collection supporting **GPU utilization** (via NVIDIA DCGM / SMI / Prometheus `container_gpu_utilization`) and **CPU utilization** (`container_cpu_usage_seconds_total`).
  - Configurable scaling parameters: target threshold % (`gbnt.autoscaling.target`, default 80%), minimum replicas floor (`gbnt.autoscaling.min`), maximum replicas ceiling (`gbnt.autoscaling.max`), and cooldown intervals (`gbnt.autoscaling.cooldown`, default 60s).
* **Hardware Affinity & Placement Strategy Enforcement:**
  - **GPU Affinity:** When `gbnt.autoscaling.metric: gpu` or `gbnt.node.gpu == nvidia` is declared with `scope: cluster`, the scheduler strictly filters candidate nodes using `docker.NodeHasGPU()`, ensuring GPU containers only schedule onto Centurions with verified NVIDIA hardware.
  - **Single-Host vs Multi-Host Containment:** Pinned hosts (`node.hostname == ...`, `node.id == ...`) and atomic stacks (`gbnt.placement.strategy: single-host`) automatically restrict autoscaling to the local host even if cluster scope is requested, preventing placement conflicts. Conversely, distributed stacks (`gbnt.placement.strategy: spread`) default to multi-node cluster scaling.
* **Web Dashboard Indicators & Interactive Control Dialog (Flutter):**
  - **Clickable AUTOSCALE Badges:** Both Legions (Stacks) and Containers (Tasks) render interactive `AUTOSCALE` chips (showing ⚡ **GPU • Cluster**, ⚡ **CPU • Host**, or clickable `Off` chip) with pointer cursors and tooltips. Clicking opens the **Autoscale Control Dialog**.
  - **Dedicated Autoscale Control Dialog:** Full-featured modal to toggle autoscaling ON/OFF, switch metrics (GPU with NVIDIA DCGM acceleration vs CPU), select scaling scope (Single Host vs All Centurions with GPU hardware affinity notes), adjust target % slider, specify min/max replica boundaries, and set cooldown periods.
  - **Row Context Actions:** Direct "Autoscale Settings" action button in Legions table and Tasks context menu.
  - **Containers (Tasks) PlutoGrid:** Dedicated `AUTOSCALE` column and context menu action to configure service autoscale directly from individual container instances.
  - **Compose Studio & Copilot:** Dedicated `Autoscale` Copilot tab with 1-click production blueprints (GPU AI/Inference, High-Load Web, Single-Host CPU) and autocomplete snippets (`gbnt.autoscaling.*`).
* **REST API Endpoints:**
  - `GET /api/autoscaling/policies`: Cluster-wide autoscaling policies breakdown.
  - `GET /api/autoscaling/events`: Audit history of scaling events and actions.
  - `POST /api/services/:id/autoscale`: Interactive horizontal autoscaling configuration update endpoint for specific services.
  - `POST /api/stack/:id/autoscale`: Interactive horizontal autoscaling configuration update endpoint for entire stacks.
  - `POST /api/services/:id/scale`: Manual replica scale override endpoint.

### 95. Spanish ENS (Esquema Nacional de Seguridad RD 311/2022) Compliance: MFA (TOTP), Forensic Audit Trail & Security Auditor Role (`v2.81.0`)
* **Multi-Factor Authentication Subsystem (TOTP RFC 6238 — ENS `op.acc.2`):**
  - **Zero-Dependency RFC 6238 TOTP Engine (`internal/auth/totp.go`):** Native Go cryptographic implementation using HMAC-SHA1 with 30-second time steps and drift tolerance ($\pm 1$ step / 30s).
  - **Base32 & Authenticator App Compatibility:** Generates standard Base32 secrets and `otpauth://totp/gubernator:<username>?secret=...&issuer=gubernator` URIs compatible with Google Authenticator, Microsoft Authenticator, 1Password, Bitwarden, and Authy.
  - **One-Time Backup Recovery Codes:** Generates 8 cryptographically secure 8-character recovery codes (`xxxx-xxxx`) hashed with bcrypt and persisted in SQLite for emergency account recovery if the 2FA device is unavailable.
  - **Issuer-Isolated Pre-Auth Challenge Tokens:** Two-step login flow issuing short-lived (`5 min`) JWT tokens (`iss: "gubernator-mfa-pending"`) that strictly authorize only the verification endpoint (`/api/auth/mfa/verify`), preventing unverified access to cluster APIs.
  - **Global Administrative Enforcement (`mfa_enforced`):** Configurable security policy requiring all administrator accounts to activate TOTP before granting cluster mutation rights.
  - **Interactive Web UI Login Flow (`web-ui/lib/screens/login_screen.dart`):** Dedicated MFA challenge card with 6-digit auto-focus monospace input, backup code support, and cancel/return actions.
  - **User Lifecycle & Self-Service Management (`web-ui/lib/screens/pages/security_page.dart`):** In-app MFA setup wizard with Base32 copy, one-time backup codes table, live code activation test, and administrative revocation.

* **Tamper-Evident Forensic Audit Trail & SIEM Syslog/CEF Forwarder (ENS `op.mon.1`):**
  - **SHA-256 Cryptographic Hash Chaining (`internal/audit/audit.go`):** Every audit log event is cryptographically linked to the previous entry via SHA-256 (`Hash = SHA-256(PrevHash + Timestamp + Username + Provider + Action + Status + Details)`), establishing an immutable Merkle-like chain where any record tampering, deletion, or injection invalidates all subsequent hashes.
  - **Cryptographic Chain Verification Engine (`audit.VerifyChainIntegrity`):** Automated integrity auditing verifying continuous sequential hash validity across all database records, exposed via `GET /api/security/audit-logs/verify`.
  - **Asynchronous SIEM Syslog / CEF Forwarder:** Non-blocking background worker with a 2,000-event buffer dispatching events in real time to enterprise SIEM platforms (Splunk, Wazuh, IBM QRadar, Elastic SIEM, Rsyslog) over UDP, TCP, or TLS.
  - **Multi-Format SIEM Transports:** Native formatting for **RFC 5424 Syslog**, **CEF (Common Event Format)**, and **JSON** with live test probe diagnostics (`POST /api/security/siem/test`).
  - **Forensic Audit Export (`GET /api/security/audit-logs/export`):** Direct file export in CSV, JSON, and Syslog format with browser download support.
  - **Cluster-Wide Audit Instrumentation:** Comprehensive event capture across stack deployment/deletion, task lifecycle actions, interactive container shells, authentication, password changes, and security configurations.

* **Security Auditor Role & Separation of Duties (ENS `org.2`):**
  - **Dedicated `auditor` Role (`RoleAuditor = "auditor"`):** Enforces strict regulatory separation between system administration and security oversight.
  - **Read-Only Audit & Observability Access:** Auditors have unrestricted inspection rights across forensic audit logs, chain integrity verification, SIEM configuration, adoption telemetry, and cluster monitoring.
  - **Strict RBAC Mutation Guardrails:** Auditors are strictly prevented from deploying or modifying stacks, restarting or deleting tasks, opening container shells, altering network mounts, or changing credentials.
  - **Directory Mapping Parity:** Supported across local user creation, Active Directory / LDAP group mapping, and OIDC claims mapping.

* **Flutter Web Security Center Dashboard Enhancements (`web-ui/lib/screens/pages/security_page.dart`):**
  - **Forensic Audit & SIEM (ENS) Tab:** Dedicated high-visibility tab with live cryptographic chain status banner (green for verified immutable chain, pulsing red alert for tampered records).
  - **Interactive SIEM & ENS Configuration Card:** Real-time form controls for SIEM Host, Port, Protocol (UDP/TCP/TLS), Format (RFC5424/CEF/JSON), Global Admin MFA toggle, live probe test, and save actions.
  - **Local Users Table MFA Column:** Visual chips displaying MFA status (`MFA Active` vs `Off`) with single-click setup and revocation modal dialogs.
  - **Audit Trail Data Table with SHA-256 Badges:** Monospace hash snippet chips with full SHA-256 / PrevHash inspection tooltips and quick-export dropdown menu (CSV, JSON, Syslog).

### 96. Google Authenticator QR Code Onboarding & Offline Multi-Factor Authentication Suite (`v2.81.1`)
* **Pure Go QR Code Engine (`internal/auth/totp.go`):**
  - Integrated `github.com/skip2/go-qrcode` for 100% offline, pure Go QR code generation (zero external CGO or third-party web service dependencies, fully air-gap compliant).
  - Generates standard 256x256 PNG images encoded into Base64 Data URIs (`data:image/png;base64,...`) from standard `otpauth://totp/Gubernator:<username>?secret=...&issuer=Gubernator` URIs.
  - Added `GenerateQRCodePNG(content, size)` and `GenerateQRCodeDataURI(content, size)` with unit test validation (`TestQRCodeGeneration`).
* **REST API QR Code Delivery (`internal/web/server.go`):**
  - `/api/auth/mfa/setup`: Now returns `qr_data_uri` alongside `secret`, `otpauth_uri`, and `backup_codes`. Supports administrative MFA onboarding for target `user_id`.
  - `/api/auth/mfa/qr`: Added direct `GET` endpoint streaming `image/png` bytes for direct browser preview or custom integrations.
  - Enhanced `/api/auth/mfa/enable` and `/api/auth/mfa/disable` to support optional target `user_id` when triggered by cluster administrators.
* **Interactive Google Authenticator Onboarding Modal (`web-ui/lib/screens/pages/security_page.dart`):**
  - **Visual QR Code Card:** Renders a clean white card with elevated drop shadow, rounded corners, and branded Google Authenticator camera badge.
  - **Seamless Offline Decoding:** Uses Flutter Web native `base64Decode` and `Image.memory` without external network calls.
  - **Collapsible Manual Fallback:** Optional toggle to display the raw Base32 secret key with one-click clipboard copy for users without a camera.
  - **Step-by-Step Security Flow:** Scan QR code -> Copy emergency single-use backup codes -> Verify 6-digit TOTP code to activate.

### 97. Grafana Dashboard Multi-Host Detailed Centurions Table Fix (`v2.81.2`)
* **Resolution of Panel 52 Error & Empty Data (`internal/monitor/gubernator_dashboard.json` & `monitoring/grafana/dashboards/gubernator.json`):**
  - **Replaced Broken `joinByLabels` Transformer:** Removed `joinByLabels` (which fails on Prometheus table-formatted frames lacking field labels metadata) and reverted to the native, battle-tested `seriesToColumns` outer join on the `instance` field.
  - **Clean Standard PromQL Expressions:** Replaced fragile `label_replace` wrappers with direct instant table PromQL queries across CPU, Memory Used %, Memory Used, Memory Total, Network Rx/Tx, and Host Disk (used, total, %).
  - **Column Alignment & Display Mode:** Configured clean `organize` transformation mapping `Value #<refId>` to descriptive metrics (`CPU Usage %`, `Memory Used %`, `Net Rx`, `Host Disk %`, etc.), hiding redundant `Time` timestamp columns, and applying `gradient-gauge` display mode on `Host Disk %`.

### 98. Industrial IoT & SCADA Simulation Subsystem (IEEE 1815 DNP3 + FUXA Web HMI) (`v2.82.0`)
* **Pure IEEE 1815-2012 (DNP3) Protocol Engine (`examples/example-scada-dnp3-fuxa/simulator/dnp3_frame.py`):**
  - Zero-external-dependency Python implementation of DNP3 Data Link, Transport, and Application layers.
  - Native CRC-16 calculation with polynomial `0xA653` (inverted output), validating 10-octet link header and 16-octet data link payload chunks.
  - Full support for Function Codes `0x01` (Read / Class 0/1/2/3 Integrity Poll), `0x81` (Response with IIN internal indications), and `0x05` (Direct Operate).
  - Implements DNP3 Object Groups: Group 1 Var 2 (Binary Input with flags), Group 12 Var 1 (Control Relay Output Block - CROB with Trip/Close/Pulse codes), and Group 30 Var 1/2 (Analog Input 32-bit/16-bit).
  - Thread-safe `DNP3MasterClient` using `threading.RLock()` for high-concurrency socket communications without deadlock.
* **Dual Industrial Field RTUs & Simulation Logic:**
  - **Substation Alpha RTU (DNP3 Address 10, Port 20000):** Simulates a 25 kV electric distribution substation. Tracks Feeder Breaker 52-1 state, Disconnector Switch 89-1, Overcurrent Relay 50/51, SF6 Gas Pressure, Busbar Voltage (25 kV), Feeder Current (120 A), Active Power (5 MW), Reactive Power (0.8 MVAr), and Transformer Temperature (58 °C). Executes CROB Direct Operate Trip (de-energizes line to 0 kV/0 A) and Close (re-energizes to 25 kV).
  - **Solar PV Farm Beta RTU (DNP3 Address 20, Port 20000):** Simulates a 3 MW utility-scale solar photovoltaic array. Tracks central inverter status, grid synchronism, anti-islanding protection, active generation curve (0-3000 kW), solar irradiance (W/m²), DC array voltage (760 V), DC array current (2400 A), and daily kWh yield. Executes CROB Direct Operate Curtailment and Inverter Run.
* **DNP3 Master Station & Bi-Directional MQTT Telemetry Bridge (`master_bridge.py`):**
  - Automated Master polling engine issuing cyclic Class 0/1/2/3 Integrity Polls across all configured outstation RTUs.
  - Transforms raw IEEE 1815 binary and analog objects into clean JSON payloads published to Eclipse Mosquitto MQTT (`scada/dnp3/substation/...` and `scada/dnp3/solar/...`).
  - Subscribes to MQTT control topics (`scada/dnp3/control/...`) and dynamically translates HMI commands into standard IEEE 1815 CROB Direct Operate frames sent over TCP.
* **Pre-Configured FUXA SCADA / HMI Project (`project.fuxap` & `project.fuxap.db`):**
  - Integrates modern open-source web SCADA platform [FUXA](https://github.com/frangoteam/FUXA) running on port `1881` (`fuxa.gbnt.local`).
  - Pre-generated SQLite project database containing an interactive Single-Line Diagram (SLD), SVG substation breaker symbols with live color state transitions (Red = Closed/Live, Green = Open/Safe), dynamic busbar energization styling, analog gauge meters, solar generation dials, alarm banners, and interactive Breaker Trip/Close action buttons.
* **Gubernator 1-Click POC Catalog Integration:**
  - Registered under the new **"IoT & Industrial SCADA"** category (`internal/examples/data/scada-dnp3-fuxa.yml`, `internal/examples/examples.go`, and `poc_examples_dialog.dart`).
  - Automated storage population via `EnsureSCADAStorageFiles()` creating `/var/contenedores/scada-dnp3/` before deployment.
  - Full CLI (`gbnt stack deploy -c examples/example-scada-dnp3-fuxa/docker-compose.yml`) and Web UI parity.

### 99. Profile-Adaptive SRE Observability UI & Enterprise SIEM Stack (`v2.83.0`)
* **Dynamic Profile-Adaptive Navigation Architecture:**
  - Backend exposes `active_sre_profile` in `/api/state` and dynamically evaluates active containers per profile (`IsRunning()`).
  - Web UI sidebar dynamically detects active SRE architecture and reorganizes navigation menus and breadcrumb titles:
    - **Enterprise SIEM (`enterprise-elk`):** "Monitoring" dynamically switches to **"OpenSearch Dashboards"** (incrusting native OpenSearch Dashboards on `:5601`), and "Loki Logs" adapts to **"SIEM & Audit Logs"** with direct integration to Lucene search and Discover.
    - **Incompatible Profile Adaptive Fallbacks (`SreFeatureAdaptivePage`):** When navigating to Grafana-dependent features like "Network Monitor" or tracing tools like "Jaeger" under an incompatible profile, the UI renders an informative architecture card explaining that the current SRE profile uses OpenSearch/Lucene or VictoriaMetrics instead of Grafana/Jaeger, with a 1-click button to open the SRE Profiles selector modal.
* **Embedded OpenSearch Dashboards with Permissive CSP:**
  - Configures `csp.allowedFrameAncestorSources: ["*"]` and `csp.warnLegacyBrowsers: false` inside auto-generated `opensearch_dashboards.yml` (`MonitorDir()/opensearch-dashboards/`).
  - Seamlessly renders the full native OpenSearch Dashboards interface inside an embedded iframe on Gubernator Web UI (`:4001`) with top action toolbar (`Perfiles SRE`, `Discover Logs`, `Direct Port :5601`).
* **OpenSearch Log Ingestion & Fluent Bit Integration:**
  - Fluent Bit daemon configured via auto-generated `fluent-bit.conf` to tail `/var/lib/docker/containers/*/*.log` and ship cluster logs directly into OpenSearch (`gbnt-monitor-opensearch:9200`) under `gubernator-logs` index.
* **Persistent Auto-Deployment & Cleanup:**
  - Expanded `AllContainers()` and `AllVolumes()` across all SRE architectures (`victoriametrics`, `clickhouse`, `opensearch`, `opensearch-dashboards`, `fluentbit`, `vector`) ensuring zero leftover containers on profile switches.
  - Server auto-deploy watchdog (`GBNT_MONITOR=true`) respects the persistent active SRE profile (`GetActiveProfile()`) or `GBNT_SRE_PROFILE` override, guaranteeing persistent reboot stability.

### 100. Out-of-the-Box OpenSearch Container Dashboards, SIEM Security Audit & Structured Log Parsing (`v2.83.1`)
* **Automated OpenSearch Dashboards Provisioning Subsystem (`internal/monitor/opensearch_provision.go`):**
  - Completely eliminates empty dashboard states upon deploying the `enterprise-elk` SIEM profile by automatically waiting for OpenSearch Dashboards on `:5601` (`/api/status`) and provisioning production-grade visual objects via Saved Objects REST API.
  - Automatically provisions `index-pattern/gubernator-logs` with explicit `attributes.fields` JSON schema mapping (`@timestamp`, `stream`, `log`, `container_log_path`, `time`), resolving field cache and metadata lookups out of the box, and sets `defaultIndex: gubernator-logs`.
  - Generates 2 pre-configured Saved Searches:
    - `gubernator-all-logs` ("Live Container Logs Stream"): Tailoring stream, log content, and container log path.
    - `gubernator-error-logs` ("Filtered Error & Warning Logs"): Targeted Lucene filter `stream: stderr OR log: *error* OR log: *fail* OR log: *exception*`.
  - Automatically deploys 6 specialized container visualizations:
    - **Total Cluster Logs** (Metric KPI).
    - **Stdout Events** (Metric KPI).
    - **Stderr & Errors** (Metric KPI with alert styling).
    - **Log Streams Breakdown** (Donut chart).
    - **Log Activity Trends Over Time** (Date Histogram area/bar chart).
    - **Top Active Containers by Log Volume** (Horizontal bar ranking).
  - Automatically deploys 2 comprehensive Dashboards configured with `timeRestore: true` and a 24-hour default time window:
    - **`[Gubernator] Container Cluster Logs Overview` (`gubernator-cluster-logs`)**: Complete cluster-wide telemetry, stream distribution, activity velocity, and live log stream.
    - **`[Gubernator] SIEM Security & Error Audit` (`gubernator-siem-audit`)**: Security and anomaly audit dashboard filtering errors, panics, and unexpected container terminations.
* **Structured Container Log Parsing via Fluent Bit v5:**
  - Auto-generates `parsers.conf` with native Docker JSON parser (`format json`, `time_key time`, `time_format %Y-%m-%dT%H:%M:%S.%L`).
  - Configures `fluent-bit.conf` with `Parsers_File parsers.conf`, `Parser docker`, `Path_Key container_log_path`, and `Buffer_Size 10M` to eliminate HTTP buffer overflow warnings during large burst ingestions.
  - Ensures raw Docker JSON string payloads are parsed into structured, searchable Elasticsearch/OpenSearch attributes (`stream`, `log`, `time`).
* **Web UI Segmented Controller Toolbar:**
  - `web-ui/lib/screens/pages/opensearch_dashboards_page.dart` features a responsive top segmented view selector enabling 1-click switching between **Logs Overview** (`#/view/gubernator-cluster-logs`), **SIEM Audit** (`#/view/gubernator-siem-audit`), and **Discover** (`/app/discover`), while retaining full access to external launch (`:5601`) and SRE Profiles configuration.

### 101. Full-Screen Embedded OpenSearch Discover & Bi-Directional SRE Profile State Restoration (`v2.83.2`)
* **Dedicated Full-Screen Embedded Discover Explorer (`OpenSearchDiscoverPage`):**
  - Completely replaces the legacy Loki Logs view when the active SRE profile is `enterprise-elk`.
  - Directly embeds OpenSearch Discover (`opensearch-discover-iframe`) across the entire screen inside Gubernator, eliminating external popup tab requirements.
  - Interactive top toolbar with quick segmented view toggling between **Live Logs Stream** (`gubernator-all-logs`) and **Errors & Security Audit** (`gubernator-error-logs`), live port :5601 badge, and direct SRE Profiles selector dialog.
* **Bi-Directional Profile Restoration Guarantee:**
  - Seamlessly reverts all navigation elements, views, and containers when switching back to the default/previous profile (`cloud-native` / `ultra-light`):
    - "OpenSearch Dashboards" automatically restores to **Monitoring** (`GrafanaPage` on `:3000`).
    - "SIEM & Audit Logs" automatically restores to **Loki Logs** (`LokiLogsPage` live querying `:3100`).
    - Incompatible feature placeholders restore to **Network Monitor** (`NetworkPage`) and **Jaeger** (`JaegerPage`).
  - Container lifecycle engine (`StopAll()`) cleanly stops and purges OpenSearch, OpenSearch Dashboards, and Fluent Bit, spinning up Prometheus, Grafana, Loki, Promtail, Jaeger, cAdvisor, and Node Exporter with zero leftover container conflicts.

### 102. OpenSearch Trace Analytics & APM Integration (`v2.83.3`)
* **OpenSearch Trace Analytics & Observability Embedding (`OpenSearchTracesPage`):**
  - Adapts the sidebar item 12 to **"Trace Analytics"** (icon `polyline`) with breadcrumb `Trace Analytics (APM)` when the active profile is `enterprise-elk`.
  - Directly embeds OpenSearch Trace Analytics / Observability (`/app/observability-dashboards#/trace_analytics/traces`), providing service dependency maps, distributed spans, P50/P90/P99 latency percentiles, and trace groups within Gubernator.
### 103. Automated Docker Daemon Metrics (Port 9323), Prometheus Telemetry & Grafana Runtime Dashboards (`v2.84.0`)
* **Zero-Touch Docker Engine Daemon Metrics Auto-Configuration (`internal/monitor/deploy.go`, `internal/cli/legion.go`, `internal/api/server.go`):**
  - Added `EnsureDockerDaemonMetrics()`: automatically checks `/etc/docker/daemon.json` on node initialization and registration (`gbnt legion init`, `gbnt legion join` / `EnsureWorkerMonitoring`, and Manager startup).
  - Guarantees `"metrics-addr": "0.0.0.0:9323"`, `"experimental": true`, and `"live-restore": true` are active without manual intervention, saving a timestamped backup (`/etc/docker/daemon.json.bak.<ts>`) and safely reloading/restarting Docker without container downtime.
* **Dynamic Prometheus Scraping Integration (`internal/monitor/configs.go`):**
  - Integrated `job_name: 'docker-daemon'` into the automated Prometheus configuration generator:
    - Manager: `'host.docker.internal:9323'`
    - Workers: `'<worker_ip>:9323'`
    - 15-second scrape interval with `service: 'docker-daemon'` label.
  - Automatically updates and reloads via SIGHUP across all node join/leave lifecycle events via `UpdatePrometheusConfig()`.
* **Dedicated Grafana Engine Runtime Dashboard Panels (`internal/monitor/gubernator_dashboard.json` & `monitoring/grafana/dashboards/gubernator.json`):**
  - Added full-width collapsible row **`"Docker Engine Daemon Runtime (Port 9323)"`** containing 4 production panels:
    1. **Active Docker Daemons (Port 9323)**: Real-time stat card tracking healthy `dockerd` engines across the cluster.
    2. **Docker Containers by State (Daemon Level)**: Stacked timeseries/bar chart breakdown showing live counts of `running`, `stopped`, and `paused` containers per Centurion node.
    3. **Docker Engine API Actions / Sec**: Real-time rate of Docker API operations processed by each daemon (`changes`, `commit`, `create`, `start`, etc.).
    4. **Docker Daemon Memory & Goroutines**: Dual-axis graph monitoring `dockerd` heap allocations (`go_memstats_alloc_bytes`) alongside active goroutines concurrency per cluster host.

### 104. Spanish ENS (RD 311/2022) Compliance Step 1: Account Lockout (op.acc.2), Administrative Unlock & Password Complexity Policy (CCN-STIC) (`v2.85.0`)
* **Automatic Account Lockout Engine (`internal/web/server.go` — ENS `op.acc.2`):**
  - Configurable brute-force mitigation policy automatically locking local user accounts after $N$ consecutive failed login attempts (`max_failed_logins`, default 5).
  - Enforces a temporal cooling-off lockout window (`lockout_duration_minutes`, default 15 minutes), rejecting incoming login requests with `HTTP 423 StatusLocked` and exact remaining minutes until unlock.
  - Automatically resets failed attempts to zero upon successful authentication with verified credentials.
* **Administrative Account Unlock API & UI Actions:**
  - Added REST endpoint `POST /api/security/users/:id/unlock` restricted to `RoleAdmin`.
  - Instantly rehabilitates locked user accounts, resets failed attempt counters, and clears `locked_until` timestamps without requiring cooling-off period expiration.
  - Injected dedicated "Desbloquear Cuenta" action button (`Icons.lock_open`) into the Local Users table in the Web Dashboard.
* **Cryptographic Password Complexity Policy (`internal/auth/password_policy.go` — CCN-STIC 823):**
  - Pure Go password validation engine enforcing minimum length ($\ge 12$ characters by default for ENS Medio/Alto).
  - Mandatory complexity requirements: checks presence of uppercase (`[A-Z]`), lowercase (`[a-z]`), numeric digits (`[0-9]`), and special symbols/punctuation (`!@#$%^&*...`).
  - Prohibits passwords matching or containing the account username and rejects trivial/common dictionary passwords.
  - Enforced across both local user creation (`POST /api/security/users`) and password reset (`POST /api/security/users/:id/password`).
* **Immutable Forensic Audit Instrumentation (ENS `op.mon.1`):**
  - Every account lockout event is cryptographically sealed into the SHA-256 hash chain with action `ACCOUNT_LOCKED` and immediately forwarded to configured SIEMs (Syslog, CEF, JSON).
  - Failed login attempts during lock emit `LOGIN_LOCKED_ATTEMPT`.
  - Administrative unlocks generate immutable audit records `ACCOUNT_UNLOCKED`.
  - Password policy violations generate `PASSWORD_POLICY_VIOLATION`.
* **Flutter Web Security Center Dashboard Enhancements (`web-ui/lib/screens/pages/security_page.dart`):**
  - **Visual Lockout Badges:** Local Users table displays prominent `🔒 Bloqueada (Xm - ENS)` chips with detailed tooltips and instant administrative unlock buttons.
  - **Policy Guidance in Modals:** Create User and Reset Password dialogs include contextual `helperText` explaining ENS op.acc.2 requirements.
  - **Global ENS Security Configuration Controls:** Added dropdown selectors and toggles to the SIEM & Global Security card for `Max Failed Logins`, `Lockout Duration`, `Password Min Length`, and `Require Complexity`.

### 105. Spanish ENS (RD 311/2022) Compliance Step 2: Automatic Session Inactivity Timeout (op.acc.2), Forensic Audit & Visual Expiry Notice (`v2.85.1`)
* **Session Inactivity Enforcement Engine (`web-ui/lib/main.dart` — ENS `op.acc.2`):**
  - Integrated cluster-wide session inactivity timeout tracking with default 15-minute expiration per RD 311/2022 and CCN-STIC recommendations.
  - Native browser event listeners (`html.window.onMouseMove`, `html.window.onKeyDown`) and Flutter touch/pointer listeners continuously monitor user activity without performance overhead.
  - Background periodic timer terminates sessions when elapsed idle time exceeds `session_timeout_minutes`.
* **Forensic Audit Logging (`internal/web/server.go` — ENS `op.mon.1`):**
  - Updated `POST /api/auth/logout` to accept optional termination reason payload (`{"reason": "INACTIVITY_TIMEOUT"}`).
  - Automatically records `SESSION_TIMEOUT` with details indicating termination under ENS `op.acc.2` into the tamper-evident SHA-256 hash chain and forwards it immediately to SIEM listeners.
* **Visual Session Expiry Warning (`web-ui/lib/screens/login_screen.dart`):**
  - Inactivity logout triggers an amber warning banner directly on the login screen informing the operator that their previous session was terminated due to inactivity under ENS `op.acc.2`.
* **Configurable Session Timeout Controls (`web-ui/lib/screens/pages/security_page.dart`):**
  - Added dedicated "Inactividad Sesión (ENS op.acc.2)" dropdown selector (5 min, 15 min ENS Medio/Alto, 30 min, 60 min) inside the SIEM & Global Security card.
  - Dynamically updates cluster configuration and synchronizes across active browser sessions.

### 106. Spanish ENS (RD 311/2022) Compliance Step 3: AES-256-GCM Streaming Encrypted Backups Engine (mp.si.2, op.exp.10) (`v2.85.2`)
* **Authenticated Streaming Encryption Engine (`internal/storage/crypto.go` — ENS `mp.si.2`):**
  - High-performance, streaming authenticated encryption utilizing **AES-256-GCM** with **PBKDF2-HMAC-SHA256** key derivation ($\ge 100,000$ iterations per CCN-STIC / NIST SP 800-38D).
  - Employs cryptographically secure random 32-byte salt and 12-byte base nonce per archive, with chunk sequence numbers bound in Additional Authenticated Data (AAD) to prevent block reordering or truncation.
  - Streaming pipeline processes arbitrary archive sizes (from small volumes to gigabytes) with constant 64 KB memory buffers.
  - Prepends cryptographic magic header `GBNTENC1` and outputs `.tar.gz.enc` format.
* **Encrypted Archive Creation & Consistent Restoration (`internal/storage/backup.go`):**
  - Extended `CreateBackup` to support optional passphrase encryption streaming directly via `io.Pipe()` with concurrent SHA-256 integrity calculation.
  - Extended `RestoreBackup` with automatic header inspection (`IsEncryptedArchive`) and on-the-fly GCM authentication and decryption, rejecting invalid passphrases or tampered blocks before unpacking files.
  - Preserved 100% backward-compatibility with existing unencrypted `.tar.gz` archives.
* **Storage Data Model & Comprehensive Unit Testing:**
  - Extended `db.Backup` model with `IsEncrypted` and `EncryptionAlgo` ("AES-256-GCM").
  - Added unit test suites `crypto_test.go` and `backup_encryption_test.go` verifying multi-chunk streams, wrong passphrase rejection, and ciphertext bit-flip tampering resistance.

### 107. Spanish ENS (RD 311/2022) Compliance Phase 2: Encrypted Backups in Repose (AES-256-GCM) with Full Web UI & CLI Parity (`v2.86.0`)
* **Interactive Web UI Encryption & Decryption Workflows (`web-ui/lib/screens/pages/storage_page.dart`):**
  - **Create Backup Dialog:** Added dedicated section *"5. CIFRADO EN REPOSO (ENS mp.si.2 / op.exp.10)"* with toggle switch for AES-256-GCM authenticated encryption, PBKDF2-SHA256 passphrase inputs, password confirmation checks, and visual ENS guidance.
  - **Restore Dialog:** Automatically detects `backup.isEncrypted` and displays an amber warning banner prompting the operator for the decryption passphrase before initiating decompression.
  - **Backups Inventory Badges:** Backups table prominently renders a green `🔒 AES-256 (ENS)` badge alongside SCHEDULED/MANUAL status chips for all cryptographically protected archives.
* **REST API Endpoints & Immutable Forensic Audit (`internal/web/server.go` — ENS `op.mon.1`):**
  - Updated `POST /api/backups/create` and `POST /api/backups/restore` to bind encryption payloads and record forensic audit events (`BACKUP_CREATE`, `BACKUP_RESTORE`).
  - Added encryption details (`AES-256-GCM (ENS mp.si.2)` vs unencrypted) and operator identity to the tamper-evident audit hash chain forwarded to SIEM listeners.
  - Hardened `POST /api/backups/upload` with automatic header inspection (`IsEncryptedArchive`), automatically marking uploaded `.tar.gz.enc` files as encrypted in the database.
* **Full CLI Parity (`internal/cli/storage.go`):**
  - Upgraded `gbnt backup ls` with dedicated `ENCRYPTION` column displaying `🔒 AES-256` or `Plain`.
  - Added flags `--encrypt` / `-e` and `--password` to `gbnt backup create`.
  - Added flag `--password` to `gbnt backup restore`.
* **Multi-Node Cluster Deployment & Live Verification:**
  - Verified end-to-end backup creation, encryption, password verification, tamper rejection, and in-place restoration across physical/virtual Centurion nodes.

### 108. Spanish ENS (RD 311/2022) Compliance Phase 3: Live Audit Engine, Compliance Dashboard & CCN-STIC Evidence Reports (`v2.87.0`)
* **Automated ENS Compliance Engine (`internal/security/ens.go`):**
  - Live heuristic and stateful evaluation of 11 technical security controls from Annex II of Spanish Royal Decree 311/2022 across 3 operational frameworks:
    - **Marco Organizativo:** `org.2` (Segregación de funciones y responsabilidades / RBAC matrix & dedicated Auditor role).
    - **Marco Operacional:** `op.acc.1` (Identificación unívoca / UUID, bcrypt & signed JWTs), `op.acc.2` (Control de acceso / 5-attempt lockout, CCN-STIC 823 password complexity, 15m session timeout), `op.acc.6` (MFA / TOTP RFC 6238), `op.exp.10` (Copias de seguridad periódicas), `op.mon.1` (Pista de auditoría forense inmutable con SHA-256 hash chain), `op.mon.2` (Monitorización SIEM continua y reenvío Syslog/CEF), `op.cont.2` (Continuidad de actividad / clúster multi-nodo HA con auto-restart).
    - **Medidas de Protección:** `mp.si.1` (Comunicaciones TLS 1.2/1.3 automáticas con Caddy Ingress), `mp.si.2` (Cifrado en reposo AES-256-GCM con PBKDF2), `mp.sw.2` (Firma criptográfica Cosign, SBOM y Gatekeeper).
  - Dynamically calculates weighted conformity percentages for tiers BÁSICO, MEDIO, and ALTO, assigning the overall qualifying category (`BASICO`, `MEDIO`, `ALTO`, or `INSUFICIENTE`).
* **REST & Web APIs (`internal/api/security_handlers.go`, `internal/web/server.go`):**
  - Exposed `GET /v1/security/ens/status` & `GET /api/security/ens/status` returning complete compliance evaluation summaries and measure details.
  - Exposed `GET /v1/security/ens/report` & `GET /api/security/ens/report` exporting formatted CommonMark technical audit reports ready for CCN-STIC submission.
* **Web UI ENS Compliance Dashboard (`web-ui/lib/screens/pages/security_page.dart`):**
  - Integrated dedicated 5th tab *"Cumplimiento ENS (RD 311/2022)"* with rich aesthetics:
    - 4 real-time KPI scorecards: Categoría Global Alcanzada, Nivel BÁSICO (%), Nivel MEDIO (%), Nivel ALTO (%).
    - Multi-dimensional filters: `Todas`, `BÁSICO`, `MEDIO`, `ALTO`, and `⚠️ Requieren Acción`.
    - Interactive measure cards with live status badges (`✅ CUMPLE (100%)`, `⚠️ PARCIAL`, `❌ NO CUMPLE (0%)`), technical evidence inspectors, and CCN-STIC remediation advice.
    - One-click CommonMark audit report export modal with live preview, clipboard copying, and `.md` file download.
* **Full CLI Parity (`internal/cli/security.go`):**
  - Added `gbnt security ens` displaying formatted terminal audit table and `gbnt security ens --report` exporting complete technical markdown reports.

### 109. Local User Temporary Suspension & Reactivation Subsystem (`v2.87.1`)
* **Instant One-Click Inline Suspension Switch (`web-ui/lib/screens/pages/security_page.dart`):**
  - Added interactive inline toggle `Switch` directly within the *Status* column of the Local Users table, displaying color-coded status badges (`🟢 Activo` vs `⏸️ Suspendido`).
  - Implemented suspension confirmation dialog preventing accidental triggers and quick pause/play icon buttons (`⏸️` / `▶️`) in the Actions row.
* **Enhanced Edit User Modal with Dedicated Status Card:**
  - Redesigned user edit dialog with a prominent "Cuenta Activa / Suspendida" status card displaying access permission indicators, descriptive subtext, and account toggle controls.
* **Lockout Safeguards & Anti-Disruption Rules (`internal/web/server.go`):**
  - Strict backend safeguards blocking attempts to suspend the primary `admin` root account or self-suspension by the currently authenticated administrator.
* **Authentication Interception & Informative Messaging:**
  - Login attempts with suspended accounts are rejected with `401 Unauthorized`, returning localized feedback (`"La cuenta de usuario está suspendida temporalmente. Contacte con un administrador."`) and flagging `"suspended": true`.
* **Tamper-Evident Forensic Audit Trail (ENS `op.mon.1` & `op.acc.2`):**
  - Dedicated audit actions `USER_SUSPEND` and `USER_REACTIVATE` cryptographically chained in the SHA-256 hash log recording actor, timestamp, IP, and targeted user account.

