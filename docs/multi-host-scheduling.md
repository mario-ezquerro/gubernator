# Multi-Host Service Placement, Anti-Affinity & Dynamic Caddy Load Balancing

## 🏛 Overview

Historically, Gubernator scheduled entire Docker Compose stacks atomically onto a single Centurion node. While atomic placement is ideal for tightly-coupled micro-stacks (e.g. an app container sharing localhost sockets or local volumes with an embedded database), enterprise production workloads demand:

1. **High Availability & Fault Tolerance**: Distributing service replicas across distinct physical Centurion nodes (Anti-Affinity / Spread) so that a failure of one server does not impact application availability.
2. **Heterogeneous Hardware Affinity**: Pinning compute-heavy or AI workloads to GPU-accelerated workers (`gbnt.node.gpu == nvidia`) while keeping stateful databases on storage-optimized hosts and web tiers across general workers.
3. **Dynamic Ingress Load Balancing**: Automatically configuring Caddy Ingress to proxy incoming HTTP/HTTPS traffic across all live replicas spanning multiple cluster nodes with health check failover.
4. **Compose Studio Integration**: Visual authoring, smart autocompletion, and starter blueprints in the Gubernator Web Dashboard.

---

## 🗺 Architecture & Scheduling Flow

```
                     ┌──────────────────────────────────────────────┐
                     │          Gubernator Compose Studio           │
                     │  (Placement & LB Copilot + Autocomplete)     │
                     └──────────────────────┬───────────────────────┘
                                            │ Save & Deploy
                                            ▼
                     ┌──────────────────────────────────────────────┐
                     │          Gubernator Core Scheduler           │
                     │           (internal/api/stack.go)            │
                     └──────┬──────────────────┬──────────────────┬─┘
                            │                  │                  │
               Replica 1    │     Replica 2    │     GPU Task     │
         (Anti-Affinity)    │(Anti-Affinity)   │   (GPU Affinity) │
                            ▼                  ▼                  ▼
                    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
                    │ Centurion W1 │   │ Centurion W2 │   │ Centurion W3 │
                    │192.168.252.36│   │192.168.252.37│   │192.168.252.38│
                    │ (:8080)      │   │ (:8080)      │   │ (GPU NVIDIA) │
                    └──────▲───────┘   └──────▲───────┘   └──────────────┘
                           │                  │
                           └──────────┬───────┘
                                      │ Upstreams (Round Robin / Least Conn)
                    ┌─────────────────┴─────────────────────────────┐
                    │               Caddy Ingress                   │
                    │   reverse_proxy 192.168.252.36:8080 ... {     │
                    │       lb_policy round_robin                   │
                    │       health_uri /health                      │
                    │   }                                           │
                    └───────────────────────────────────────────────┘
```

---

## ⚙️ Configuration & Compose Syntax

### 1. Anti-Affinity & Replica Spread

To spread service replicas across distinct physical Centurion hosts, specify `deploy.placement.preferences` or use Gubernator placement labels:

```yaml
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    labels:
      - "ingress.host=web.gbnt.local"
      - "gbnt.caddy.port=8080"
      - "gbnt.placement.strategy=spread"
    deploy:
      replicas: 3
      placement:
        preferences:
          - spread: node.id
        constraints:
          - "node.role == worker"
```

* **`spread: node.id`**: Tells Gubernator to distribute each replica to a different node.
* **Least-Loaded Fallback**: If the cluster has fewer worker nodes than the desired number of replicas (e.g. 4 replicas on 3 nodes), Gubernator spreads the first 3 replicas across the 3 distinct nodes and places the 4th replica on the least-loaded node.

---

### 2. Caddy Dynamic Load Balancing & Active Health Checks

When a service has multiple replicas running across different Centurions, Gubernator's Caddy Ingress generator (`internal/aqueducts/ingress.go`) automatically collects all active host `(IP, Port)` tuples and generates a multi-upstream reverse proxy block.

Supported labels:

| Label | Description | Default | Values |
| --- | --- | --- | --- |
| `gbnt.caddy.lb` / `ingress.lb` | Load balancing policy | `round_robin` | `round_robin`, `least_conn`, `ip_hash`, `first`, `random` |
| `gbnt.caddy.health_uri` | Active health check probe URI | None | e.g. `/health`, `/healthz`, `/` |
| `gbnt.caddy.health_interval` | Interval between active health probes | `5s` | e.g. `2s`, `5s`, `10s` |
| `gbnt.caddy.health_timeout` | Probe timeout before marking upstream down | `2s` | e.g. `1s`, `2s`, `5s` |

#### Example Caddyfile Output
```caddyfile
web.gbnt.local {
    tls internal
    reverse_proxy 192.168.252.36:8080 192.168.252.37:8080 192.168.252.38:8080 {
        lb_policy round_robin
        health_uri /health
        health_interval 5s
        health_timeout 2s
    }
}
```

If a worker node goes down or a container fails its `/health` check, Caddy immediately routes traffic to the remaining healthy upstreams with zero dropped connections.

---

### 3. Specialized Hardware & Node Affinity

Services within the same stack can specify distinct constraints to target specialized hardware:

```yaml
services:
  # Web frontend distributed across worker nodes
  frontend:
    image: my-frontend:latest
    deploy:
      replicas: 2
      placement:
        preferences:
          - spread: node.id
        constraints:
          - "node.role == worker"

  # GPU AI inference task pinned to NVIDIA hardware
  ai-inference:
    image: ollama/ollama:latest
    deploy:
      replicas: 1
      placement:
        constraints:
          - "gbnt.node.gpu == nvidia"

  # Stateful database pinned to manager or specific host
  database:
    image: postgres:16-alpine
    volumes:
      - /var/contenedores/${STACK_NAME}/pgdata:/var/lib/postgresql/data
    deploy:
      replicas: 1
      placement:
        constraints:
          - "node.hostname == gbnt-manager"
```

Supported constraint keys:
* `node.role == worker` / `node.role == manager`
* `node.hostname == <hostname>` / `node.id == <node-id>`
* `gbnt.node.gpu == nvidia` / `node.labels.gpu == nvidia`
* `gbnt.node.zone == europe-1` / `node.labels.<key> == <value>`

---

## 🎨 Compose Studio Features

### 1. Placement & LB Copilot Wizard
In Compose Studio, the **Placement & LB** tab (cyan hub icon `Icons.alt_route`) provides:
* **Anti-Affinity Snippets**: 1-click insertion of `spread: node.id` and `gbnt.placement.strategy=spread`.
* **Caddy Load Balancing Presets**:
  * Round Robin Policy
  * Least Connections Policy
  * IP Hash (Sticky Sessions)
  * Active Health Check Probes
* **Centurion Node Hardware**:
  * Worker Nodes Only
  * NVIDIA GPU Accelerated Node
  * Live clickable list of Centurion nodes to pin containers directly.

### 2. Autocomplete Bar
Typing in Compose Studio suggests:
* `placement.spread`: inserts `preferences: [spread: node.id]`
* `gbnt.placement.strategy`: inserts `gbnt.placement.strategy=spread`
* `gbnt.caddy.lb`: inserts `gbnt.caddy.lb=round_robin`
* `gbnt.caddy.health_uri`: inserts `gbnt.caddy.health_uri=/health`

### 3. Starter Blueprint: "Multi-Host Load Balanced Web"
Available in the Compose Studio template dropdown:
* 3 Nginx replicas spread across worker nodes
* Caddy Ingress with Round Robin load balancing and active health check
* Resource reservations and limits preconfigured
