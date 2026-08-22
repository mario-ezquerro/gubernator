# 🏛️ Gubernator — GlusterFS Distributed Cluster Storage Specification

> **Subsystem:** The Granaries: GlusterFS Mesh  
> **Version:** `v2.30.0+`  
> **Target Topology:** 3-Node High-Availability Cluster (Manager + 2 Workers / Centurions)

---

## 📋 Executive Overview

In multi-node container orchestration environments, stateful workloads (such as Postgres, MySQL, Redis, persistent configuration folders, and CMS assets) require **storage mobility**: if a container fails or is rescheduled to a different Centurion node, its data must remain accessible immediately with zero data loss and without manual volume reconfiguration.

Gubernator provides native, automated management of **GlusterFS distributed and replicated cluster storage** (`Replica 3` and `Replica 2 + Arbiter 1`), tightly coupled with the host `/etc/fstab` subsystem, container-level write-behind caching, live split-brain & self-healing diagnostics, and full Prometheus observability.

```
                  ┌────────────────────────────────────────────────────────┐
                  │          Gubernator Cluster Storage Mesh               │
                  └────────────────────────────────────────────────────────┘
                                              │
           ┌──────────────────────────────────┼──────────────────────────────────┐
           ▼                                  ▼                                  ▼
 ┌───────────────────┐              ┌───────────────────┐              ┌───────────────────┐
 │   Centurion 1     │   TCP Mesh   │   Centurion 2     │   TCP Mesh   │   Centurion 3     │
 │    (Manager)      │◄────────────►│   (Worker 1)      │◄────────────►│   (Worker 2)      │
 │  192.168.252.27   │  24007/49152 │  192.168.252.28   │  24007/49152 │  192.168.252.29   │
 ├───────────────────┤              ├───────────────────┤              ├───────────────────┤
 │ Brick 1:          │              │ Brick 2:          │              │ Brick 3:          │
 │ /data/glusterfs/  │              │ /data/glusterfs/  │              │ /data/glusterfs/  │
 │ brick1/gv_data    │              │ brick1/gv_data    │              │ brick1/gv_data    │
 └─────────┬─────────┘              └─────────┬─────────┘              └─────────┬─────────┘
           │                                  │                                  │
           └──────────────────────────────────┼──────────────────────────────────┘
                                              ▼
                           ┌─────────────────────────────────────┐
                           │      Shared Replicated Mount:       │
                           │         /var/contenedores           │
                           │   (Replica 3 — 3-Way Mirrored)      │
                           └──────────────────┬──────────────────┘
                                              │
                                              ▼
                           ┌─────────────────────────────────────┐
                           │         Docker Containers           │
                           │  -v /var/contenedores/app:/var/data │
                           └─────────────────────────────────────┘
```

---

## ⚖️ Technology Trade-Offs: Why GlusterFS for 3 Nodes?

| Feature | GlusterFS (`Replica 3`) 🏆 | CephFS | GFS2 / OCFS2 |
| :--- | :--- | :--- | :--- |
| **Minimum Node Footprint** | **3 nodes** (1 Manager + 2 Workers) | 3-5 nodes (Monitors + OSDs + MDS + MGR) | 2-3 nodes + Hardware SAN / iSCSI LUN |
| **RAM Overhead** | **~150 MB per node** | 2-4 GB per OSD/Daemon | ~100 MB |
| **Underlying Filesystem** | Standard POSIX (ext4 / XFS) | Raw block devices (BlueStore) | Shared block device with DLM locking |
| **Quorum & Split-Brain** | Built-in 3-way quorum / Arbiter | Complex Paxos monitor quorum | External hardware fencing (STONITH / IPMI) |
| **Kernel / Fuse Client** | Native FUSE + GlusterFS client | FUSE / Kernel Ceph module | Kernel GFS2 module + DLM cluster lock |
| **Container Optimization** | Client write-behind & stat-prefetch | High-performance (heavy setup) | High risk of kernel hangs on node crash |

---

## ⚙️ Container-Grade Performance Tuning

Container workloads generate bursty metadata queries, directory traversals, and small file writes. When creating a GlusterFS volume via Gubernator (REST API, CLI, UI, or Ansible), the engine automatically configures the following production parameters:

```bash
# High-speed write aggregation and asynchronous flush
gluster volume set <volume> performance.write-behind on
gluster volume set <volume> performance.flush-behind on

# Aggressive metadata and directory caching
gluster volume set <volume> performance.stat-prefetch on
gluster volume set <volume> performance.read-ahead on
gluster volume set <volume> performance.quick-read on
gluster volume set <volume> performance.io-cache on

# Fast network failover for container resilience
gluster volume set <volume> network.ping-timeout 10

# Automatic conflict resolution by modified timestamp
gluster volume set <volume> cluster.favorite-child-policy mtime
```

---

## 🔗 High-Availability `/etc/fstab` Auto-Mount

To ensure zero-downtime container resilience, Gubernator mounts the GlusterFS volume to `/var/contenedores` with **backup volfile servers**:

```ini
# /etc/fstab entry generated by Gubernator
localhost:/gv_contenedores /var/contenedores glusterfs defaults,_netdev,backup-volfile-servers=192.168.252.27:192.168.252.28:192.168.252.29 0 0
```

* **`localhost:/<volume>`**: Connects to the local `glusterd` instance for minimal latency.
* **`backup-volfile-servers`**: If the local node is rebooting or restarted, the FUSE client automatically fetches volume configuration from the remaining cluster peers without dropping mount I/O.
* **`_netdev`**: Ensures mounts are executed only after the network stack is fully operational.

---

## 📊 Live Observability & Prometheus Metrics

Gubernator exports real-time GlusterFS health and capacity metrics on port **4002** (`/metrics`):

| Metric Name | Type | Description |
| :--- | :--- | :--- |
| `gbnt_gluster_health_score` | Gauge | Global cluster storage health score (`0-100%`). |
| `gbnt_gluster_daemon_running` | Gauge | State of the local `glusterd` service (`1` = active, `0` = inactive). |
| `gbnt_gluster_peers_total` | Gauge | Total registered peers in the trusted storage pool. |
| `gbnt_gluster_peers_connected` | Gauge | Count of currently connected and communicating peers. |
| `gbnt_gluster_volumes_total` | Gauge | Total managed GlusterFS volumes. |
| `gbnt_gluster_volume_status` | Gauge | Volume status (`volume`, `type`, `replica_count`) (`1` = Started, `0` = Stopped). |
| `gbnt_gluster_volume_capacity_bytes` | Gauge | Capacity breakdown in bytes (`kind="total|used|free"`). |
| `gbnt_gluster_volume_bricks_total` | Gauge | Total bricks configured for the volume. |
| `gbnt_gluster_volume_bricks_online` | Gauge | Bricks currently online and healthy. |
| `gbnt_gluster_volume_pending_heals` | Gauge | Number of files awaiting synchronization in the heal queue. |
| `gbnt_gluster_volume_split_brain` | Gauge | Split-brain condition alarm (`1` = alert, `0` = healthy). |

---

## 💻 Complete CLI Command Suite (`gbnt gluster`)

```bash
# 1. Cluster health & diagnostic report
gbnt gluster status

# 2. List peers in the trusted storage pool
gbnt gluster peer-ls

# 3. Probe a new node into the pool
gbnt gluster probe 192.168.252.28

# 4. Detach a node from the pool
gbnt gluster detach 192.168.252.28

# 5. List all replicated volumes with capacity
gbnt gluster ls

# 6. Create and tune a 3-way replicated volume
gbnt gluster create gv_contenedores --replica 3 --brick-dir /data/glusterfs/brick1 --mount /var/contenedores --auto-mount

# 7. Start or stop a volume
gbnt gluster start gv_contenedores
gbnt gluster stop gv_contenedores --force

# 8. Check self-healing status & split-brain diagnostics
gbnt gluster heal gv_contenedores

# 9. Trigger immediate cluster-wide self-heal
gbnt gluster heal gv_contenedores --trigger

# 10. Auto-mount volume to /var/contenedores on all cluster hosts
gbnt gluster mount gv_contenedores --mount-point /var/contenedores

# 11. Delete a volume
gbnt gluster rm gv_contenedores
```

---

## 🤖 Automated Provisioning with Ansible (`ansible/glusterfs.yml`)

Provision the complete 3-node GlusterFS cluster in one command:

```bash
cd ansible
ansible-playbook -i inventory.ini glusterfs.yml
```

The playbook automates:
1. Package installation (`glusterfs-server`, `glusterfs-client`, `attr`) across Debian/Ubuntu and RHEL/Rocky.
2. Firewall rule configuration (`TCP 24007`, `24008`, `49152:49251`).
3. Service enablement and brick directory creation (`/data/glusterfs/brick1/gv_contenedores`).
4. Peer probe from Manager to all Worker Centurions.
5. Volume creation (`Replica 3`), performance tuning, and volume startup.
6. Safe `/etc/fstab` synchronization and mounting to `/var/contenedores`.
