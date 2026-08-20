# SPEC-storage-backups.md — Gubernator Storage & Backups Subsystem Specification

## 1. Overview & Vision

Gubernator's **Storage & Backups Subsystem** (*The Granaries / Graneros del Imperio*) provides multi-node volume discovery, cluster-wide persistent storage mobility (e.g. shared `/var/contenedores` mounts via NFS/GlusterFS/CephFS/CIFS or local volumes), on-demand and scheduled compressed backups (`.tar.gz`), one-click restoration, and storage pool health diagnostics.

---

## 2. Architectural Design

```
                      +------------------------------------------+
                      |         Gubernator Web Dashboard         |
                      |        (Storage & Backups Suite)         |
                      +------------------------------------------+
                                           |
                                           v REST API (Port 4000)
                      +------------------------------------------+
                      |       Gubernator Manager (Go API)        |
                      |   - Volume Discovery Engine              |
                      |   - Backup & Restore Manager (tar.gz)    |
                      |   - Cron Scheduler & Retention Daemon    |
                      |   - Storage Pools Health Verifier        |
                      +------------------------------------------+
                               /            |            \
                              /             |             \
                             v              v              v
                     +---------------+ +---------------+ +---------------+
                     |    Manager    | |    Worker 1   | |    Worker 2   |
                     | Node Storage  | | Node Storage  | | Node Storage  |
                     +---------------+ +---------------+ +---------------+
                            \               |               /
                             \              |              /
                              v             v             v
                     +-------------------------------------------+
                     |        Cluster Shared Storage Pool        |
                     |    e.g. /var/contenedores (NFS/Gluster)   |
                     +-------------------------------------------+
```

### Key Components:
- **Shared Storage Pools (`/var/contenedores`)**: When nodes share a network mount, containers can migrate seamlessly between Centurion nodes while accessing the exact same persistent data.
- **Volume Discovery**: Auto-detects Docker Named Volumes and Stack Bind Mounts across all active services.
- **Compressed Point-in-Time Snapshots**: Creates `.tar.gz` archives with cryptographic SHA-256 integrity verification.
- **Consistency Engine**: Supports optional `docker pause` / `docker unpause` during backup execution for database and stateful services.
- **Automated Retention & Scheduling**: Background cron daemon executing backup policies and pruning archives exceeding retention limits.

---

## 3. Feature Matrix (4 Specialized Modules)

| Module | Features & Capabilities |
| --- | --- |
| **1. Volume Explorer** | Discovers all active volumes, categorizes by type (*Shared Pool `/var/contenedores`*, *Docker Volume*, *Host Bind*), shows associated Stack & Service, displays disk usage, and provides 1-click snapshot creation. |
| **2. Backups & Snapshots** | Catalog of all backups, file sizes, creation timestamps, SHA-256 hashes, in-place or custom target restoration, direct browser `.tar.gz` download, manual backup creator with container freeze toggle, and external backup file upload. |
| **3. Schedules & Policies** | Automated cron routines (Daily, Weekly, Custom), stack selectors, and automated retention policies (e.g., keep last N backups with automatic rotation). |
| **4. Storage Pools** | Configurable base directory (`/var/contenedores`), live health check matrix across Manager and Workers (verifies folder existence, read/write permissions, and filesystem mount), and disk capacity meter (Total, Used, Free). |

---

## 4. REST API Specification

### 4.1 Volume Discovery
- `GET /v1/storage/volumes` — List all discovered volumes across the cluster with disk usage and stack mappings.

### 4.2 Storage Pools Health
- `GET /v1/storage/pools/health` — Check `/var/contenedores` accessibility and disk space across all nodes.

### 4.3 Backup Lifecycle
- `GET /v1/backups` — List all backup archives and metadata.
- `POST /v1/backups/create` — Trigger an immediate backup of a volume or stack.
- `POST /v1/backups/restore` — Restore a backup archive into a target path or volume.
- `GET /v1/backups/download/:id` — Download backup `.tar.gz` archive.
- `POST /v1/backups/upload` — Upload an external `.tar.gz` backup archive.
- `DELETE /v1/backups/:id` — Delete a backup archive.

### 4.4 Backup Schedules & Policies
- `GET /v1/backups/schedules` — List automated backup schedules.
- `POST /v1/backups/schedules` — Create or update a backup schedule.
- `DELETE /v1/backups/schedules/:id` — Delete a backup schedule.

---

## 5. CLI Command Reference

* `gbnt volume ls` — List all persistent volumes in the cluster.
* `gbnt backup ls` — List all backups.
* `gbnt backup create <stack|volume>` — Create a compressed backup archive.
* `gbnt backup restore <backup_id>` — Restore a backup.
* `gbnt backup schedule ls` — List active backup schedules.
