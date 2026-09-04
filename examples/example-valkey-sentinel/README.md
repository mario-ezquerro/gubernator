# High-Availability In-Memory Caching & Sentinel Cluster

Fault-tolerant distributed caching stack using **Valkey** (the Linux Foundation Redis alternative) with automatic master-replica failover.

## 🏛️ Components
1. **`valkey-master`**: Primary writable in-memory database with Append-Only File (AOF) persistence.
2. **`valkey-replica`**: Read-only replication instance targeted to worker Centurions.
3. **`valkey-sentinel`**: Monitoring and quorum failover daemon promoting the replica if master goes down.

## 🚀 Gubernator Features Utilized
* **Multi-Node Spread**: Placement constraints separate master and replica onto different Centurion hosts.
* **CoreDNS Health Discovery**: Containers discover the active primary via `master.cache.gbnt.local:6379`.
* **Granaries Shared Mounts**: Data persisted in `/var/contenedores/valkey`.

## 💻 Quick Deploy
```bash
gbnt examples deploy valkey-sentinel
```
