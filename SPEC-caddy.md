# SPEC-caddy.md — Gubernator Caddy Ingress Subsystem Specification

## 1. Overview & Vision

Gubernator's **Caddy Ingress Subsystem** provides multi-host reverse proxying, TLS termination, dynamic site block routing, and real-time observability across all nodes (Managers and Workers) in a Gubernator cluster.

This specification outlines the architecture, API surface, data structures, and Web UI visualization suite for managing **multi-Caddy deployments (3+ Caddy instances)**, drawing inspiration from [caddy-ui](https://github.com/zackwag/caddy-ui).

---

## 2. Architectural Design

```
                     +---------------------------------+
                     |    Gubernator Web Dashboard     |
                     | (Flutter Web UI - Caddy Suite)  |
                     +---------------------------------+
                                      |
                                      v REST API (Port 4000)
                     +---------------------------------+
                     |   Gubernator Manager (Go API)   |
                     +---------------------------------+
                        /             |             \
                       /              |              \
                      v               v               v
             +------------------+ +------------------+ +------------------+
             | Node 1 (Manager) | |  Node 2 (Worker) | |  Node 3 (Worker) |
             |  `gbnt-caddy`    | |   `gbnt-caddy`   | |   `gbnt-caddy`   |
             |  (Ports 80/443)  | |   (Ports 80/443)  | |   (Ports 80/443)  |
             +------------------+ +------------------+ +------------------+
```

### Key Components:
- **Node-Local Proxy Instances (`gbnt-caddy`)**: Each active node runs a standard `caddy:latest` container attached to the `gbnt-net` Docker overlay network and internal CoreDNS (`127.0.0.1:53`).
- **Dynamic Caddyfile Generation**: Gubernator inspects Compose stacks for `ingress.host` placement constraints and container ports, generating node-specific Caddyfiles with automatic `reverse_proxy` directives.
- **Observability Integration**: Caddy exposes administrative endpoints (`:2019/metrics` for Prometheus, `:2019/config/` for JSON state) enabling real-time metrics, SSE log tailing, and certificate status inspection.

---

## 3. Feature Matrix (Inspired by `caddy-ui`)

| Module | Features & Capabilities |
| --- | --- |
| **1. Dashboard** | Live server status across all 3 Caddy instances, TLS state (internal CA / ACME), server block summaries with display names, upstream health overview, and Caddy process stats (version, uptime, memory usage, last reload timestamp). |
| **2. Route Manager** | Route matrix across server blocks, live upstream health checks, uptime %, domain search & filtering, clickable domain & upstream links, in-place route editing, and per-route notes. |
| **3. Caddyfile Editor** | Real-time Caddyfile viewer & editor, syntax validation, `caddy fmt` formatting, site block auto-sorting, version history with backups, inline preview, and 1-click rollback. |
| **4. TLS Certificates** | Certificate status, expiration countdowns, sortable domain list, orphaned certificate detection & cleanup, and **Root CA Download** (`root.crt`) with step-by-step installation instructions for macOS, Linux, and Windows. |
| **5. Access Logs** | Tail live access logs with SSE/WebSocket streaming, real-time keyword search, log level filters (`ERROR`, `WARN`, `INFO`), auto-scroll, and export in JSON or plain text formats. |
| **6. Log Configuration** | Direct UI toggles to enable/disable and configure Caddy access logging per site block. |
| **7. Prometheus Metrics** | Total request count, RPS gauge, average response latency, HTTP status code breakdown (`2xx`, `3xx`, `4xx`, `5xx`), and latency percentiles (`p50`, `p95`, `p99`) powered by Caddy's built-in `:2019/metrics` endpoint. |
| **8. Theme & Deep Linking** | Responsive layout supporting Dark & Warm Light modes, URL-based sub-tab navigation (`/caddy?tab=dashboard`, `/caddy?tab=routes`, `/caddy?tab=editor`, etc.), and deep links. |

---

## 4. REST API Specification

### 4.1 Node Status & Process Overview
`GET /v1/caddy/status?node_id={nodeID}`

**Response Body:**
```json
{
  "node_id": "node-local-manager",
  "status": "running",
  "version": "v2.8.4",
  "uptime_seconds": 86400,
  "memory_bytes": 45120000,
  "last_reload": "2026-08-09T08:00:00Z",
  "instances_active": 3,
  "total_routes": 12,
  "tls_certificates_active": 4
}
```

### 4.2 Route Manager
`GET /v1/caddy/routes?node_id={nodeID}`

**Response Body:**
```json
{
  "routes": [
    {
      "host": "jupyter.gbnt.local",
      "upstreams": ["172.18.0.4:8888", "172.18.0.5:8888"],
      "health": "healthy",
      "uptime_percent": 99.98,
      "notes": "Jupyter Notebook AI Stack"
    }
  ]
}
```

### 4.3 Caddyfile Operations
- `GET /v1/caddy/caddyfile?node_id={nodeID}` — Get raw Caddyfile.
- `POST /v1/caddy/caddyfile` — Update Caddyfile with automatic backup creation.
- `POST /v1/caddy/fmt` — Format Caddyfile content via `caddy fmt`.
- `GET /v1/caddy/history` — Get Caddyfile backup history.
- `POST /v1/caddy/rollback` — Revert to selected historical Caddyfile backup.

### 4.4 TLS Certificates & Root CA Download
- `GET /v1/caddy/certs` — List managed TLS certificates, expiration dates, and orphan flags.
- `GET /v1/caddy/ca.crt` — Download Caddy's internal Root CA certificate (`root.crt`).
- `DELETE /v1/caddy/certs/orphaned` — Prune unused/orphaned certificates.

### 4.5 Access Logs & Streaming
- `GET /v1/caddy/logs?stream=true&level=INFO&search=jupyter` — SSE stream of access logs.
- `PUT /v1/caddy/log-config` — Enable or disable access logging for specific site blocks.

### 4.6 Prometheus Metrics
`GET /v1/caddy/metrics?node_id={nodeID}`

**Response Body:**
```json
{
  "request_count": 14250,
  "rps": 12.4,
  "avg_latency_ms": 14.2,
  "p50_latency_ms": 8.1,
  "p95_latency_ms": 32.4,
  "p99_latency_ms": 85.0,
  "status_codes": {
    "2xx": 13800,
    "3xx": 300,
    "4xx": 120,
    "5xx": 30
  }
}
```

---

## 5. Root CA Certificate Trust Guide

To trust Caddy's self-signed local HTTPS certificates across operating systems:

### macOS:
```bash
curl -o caddy-root.crt http://localhost:4000/v1/caddy/ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./caddy-root.crt
```

### Linux (Ubuntu/Debian):
```bash
curl -o /usr/local/share/ca-certificates/caddy-root.crt http://localhost:4000/v1/caddy/ca.crt
sudo update-ca-certificates
```

### Windows (PowerShell Administrator):
```powershell
Invoke-WebRequest -Uri "http://localhost:4000/v1/caddy/ca.crt" -OutFile "caddy-root.crt"
Import-Certificate -FilePath ".\caddy-root.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

---

## 6. Development & Deployment Guidelines

1. **Multi-Node Sync**: When `gbnt stack deploy` is executed on the Manager, the Manager broadcasts updated Caddyfile blocks to all worker nodes running `gbnt-caddy`.
2. **Backward Compatibility**: `ingress.host` Compose labels automatically translate into Caddy reverse proxy blocks without requiring manual Caddyfile editing.
3. **Observability**: Metrics on port 2019 are scraped by Gubernator's Prometheus engine and presented in the `CaddyPage` Metrics tab.
