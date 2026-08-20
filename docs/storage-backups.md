# Storage & Backups (The Granaries) Subsystem

Gubernator features a native **Storage & Backups Subsystem** (*The Granaries / Graneros del Imperio*) designed to provide multi-node volume discovery, cluster-wide persistent storage mobility (e.g. shared `/var/contenedores` mounts via NFS/GlusterFS/CephFS/CIFS or local volumes), point-in-time compressed backups (`.tar.gz`), one-click restoration, automated cron retention policies, and shared storage pool diagnostics.

---

## 🏛 Architecture & Container Mobility

In a multi-node cluster, stateful services (databases, file uploads, persistent caches) must retain their data when containers are rescheduled or migrated across Centurion nodes.

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

When all nodes share `/var/contenedores`, containers writing to `/var/contenedores/<stack>/data` can move from `gbnt-worker1` to `gbnt-worker2` without losing any disk modifications.

---

## 🎨 Web UI Visualization Suite

Access **Storage & Backups** in the Web Dashboard (Port 4001) to interact with 4 specialized tabs:

### 1. 📦 Volumes (Volume Explorer)
* **Cluster-Wide Volume Discovery**: Auto-detects Docker Named Volumes, Shared Pool directories (`/var/contenedores/`), and Host Bind Mounts.
* **Metadata & Disk Usage**: Displays associated Stack (Legion), Service, source and target paths, and exact size on disk.
* **1-Click Snapshot**: Instantly trigger a point-in-time backup for any discovered volume.

### 2. 💾 Backups & Snapshots
* **Compressed Archives (`.tar.gz`)**: Full catalog of all backups with file size, creation timestamp, and cryptographic SHA-256 integrity hash.
* **Container Consistency Toggle**: Supports freezing write operations (`docker pause` ➔ archive ➔ `docker unpause`) to guarantee 100% database consistency.
* **1-Click Restore**: Restore backups in-place over the original volume or clone into a custom target path.
* **Direct Download**: Download `.tar.gz` archives straight to your browser.
* **External Upload**: Upload external `.tar.gz` backup files directly into the cluster storage repository.

### 3. ⏰ Schedules & Policies
* **Automated Cron Routines**: Schedule periodic backups (Daily at 03:00 AM, Weekly on Sunday, or custom Cron expressions).
* **Automatic Retention Rotation**: Automatically keeps the last $N$ backups (e.g. 7 daily copies) and prunes older archives to prevent disk exhaustion.

### 4. 🏢 Storage Pools
* **Shared Mount Verification**: Validates whether `/var/contenedores` is accessible and writable (`rw`) across all Centurion nodes.
* **Capacity Meter**: Real-time visualization of Total, Used, and Free disk capacity.
* **Mount Helpers**: Built-in instructions for mounting NFS / GlusterFS / CephFS across nodes.

---

## 🛠️ Step-by-Step Guide: Shared Storage Setup (`/var/contenedores`)

To enable shared cluster storage across 3 nodes:

### 1. Setup NFS Server (e.g., on Manager or NAS)
```bash
sudo apt-get install nfs-kernel-server
sudo mkdir -p /srv/nfs/contenedores
sudo chown -R nobody:nogroup /srv/nfs/contenedores
sudo chmod 777 /srv/nfs/contenedores
echo "/srv/nfs/contenedores *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
```

### 2. Mount on All Centurion Nodes (Manager & Workers)
```bash
sudo apt-get install nfs-common
sudo mkdir -p /var/contenedores
sudo mount -t nfs <NFS_SERVER_IP>:/srv/nfs/contenedores /var/contenedores
```
*(Add to `/etc/fstab` for automatic mounting on reboot)*:
```text
<NFS_SERVER_IP>:/srv/nfs/contenedores /var/contenedores nfs defaults 0 0
```

---

## 🚀 Docker Compose Example with Persistent Storage

```yaml
version: '3.8'

services:
  database:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: user
      POSTGRES_PASSWORD: secretpassword
    volumes:
      # Persistent data stored in shared pool for cluster mobility
      - /var/contenedores/myapp/postgres:/var/lib/postgresql/data
    deploy:
      placement:
        constraints:
          - stack.name == myapp

  web:
    image: nginxdemos/hello:plain-text
    ports:
      - "80"
    deploy:
      replicas: 2
      placement:
        constraints:
          - stack.name == myapp
          - ingress.host == myapp.gbnt.local
```

---

## 💻 CLI Command Reference

### List Volumes
```bash
gbnt volume ls
```

### Create Backup
```bash
gbnt backup create myapp --name "pre-upgrade-backup" --pause
```

### List Backups
```bash
gbnt backup ls
```

### Restore Backup
```bash
gbnt backup restore <BACKUP_ID> --target /var/contenedores/myapp/postgres
```

### List Backup Schedules
```bash
gbnt backup schedule ls
```

---

## 📡 REST API Reference

| Endpoint | Method | Role | Description |
| :--- | :--- | :--- | :--- |
| `/v1/storage/volumes` | `GET` | `all` | List all cluster persistent volumes and sizes |
| `/v1/storage/pools/health` | `GET` | `all` | Check health and capacity of `/var/contenedores` |
| `/v1/backups` | `GET` | `all` | List all backup archives and metadata |
| `/v1/backups/create` | `POST` | `operator` | Trigger point-in-time compressed backup |
| `/v1/backups/restore` | `POST` | `operator` | Restore a backup to target directory |
| `/v1/backups/download/:id`| `GET` | `all` | Download `.tar.gz` archive |
| `/v1/backups/upload` | `POST` | `operator` | Upload external `.tar.gz` backup |
| `/v1/backups/:id` | `DELETE`| `operator` | Delete a backup archive |
| `/v1/backups/schedules` | `GET` | `all` | List backup schedules |
| `/v1/backups/schedules` | `POST` | `admin` | Create or update a backup schedule |
| `/v1/backups/schedules/:id` | `DELETE` | `admin` | Delete a backup schedule |
