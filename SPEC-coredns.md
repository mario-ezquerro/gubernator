# SPEC-coredns.md — Gubernator CoreDNS Management Suite Specification

## 1. Executive Summary

Gubernator integrates **CoreDNS** as its native internal Service Discovery and DNS resolution engine. Every container launched by Gubernator is automatically configured with `--dns <CoreDNS_IP>`, resolving `*.gbnt` internal domain names across multi-node clusters.

This specification details the expansion of CoreDNS management into a **4-Tab CoreDNS Management Suite** within the Web Dashboard and REST API, supporting **Custom Static DNS Records (A, AAAA, CNAME, TXT, PTR)**, an **Interactive DNS Playground (`Dig / Nslookup`)**, **Upstream Forwarder Controls**, and **Real-Time Health Status**.

---

## 2. System Architecture & Components

```
+-------------------------------------------------------------------------+
|                         GUBERNATOR WEB DASHBOARD                        |
|                                                                         |
|  [Tab 1: Auto-Discovered] [Tab 2: Custom Records] [Tab 3: DNS Playground] [Tab 4: Config]
+-------------------------------------------------------------------------+
                                    | REST API (/v1/coredns/*)
                                    v
+-------------------------------------------------------------------------+
|                          GUBERNATOR CORE ENGINE                         |
|                                                                         |
|  - Dynamic Hosts Generator (DB Custom Records + Container State)        |
|  - Go DNS Resolver Engine (net.Resolver on 127.0.0.1:5354)              |
|  - SIGHUP Volume Sync & Container Health Monitor                        |
+-------------------------------------------------------------------------+
                                    | Updates /etc/coredns/gubernator.hosts
                                    v
+-------------------------------------------------------------------------+
|                         CoreDNS Container (gbnt-coredns)               |
|                                                                         |
|  - Port 53 / 5354 (UDP+TCP)                                             |
|  - Plugins: hosts, template, forward, cache, log, errors                |
+-------------------------------------------------------------------------+
```

---

## 3. Database Schema (`CustomDNSRecords`)

Stored in Gubernator's SQLite relational database on the Manager node:

| Column | Type | Description |
| --- | --- | --- |
| `id` | `VARCHAR(36)` (UUID) | Primary Key |
| `domain` | `VARCHAR(255)` | Domain name (e.g. `db.internal.gbnt`, `api.mycompany.test`) |
| `ip` | `VARCHAR(255)` | Target IP address or record value (e.g. `192.168.1.100`) |
| `record_type` | `VARCHAR(10)` | Record Type (`A`, `AAAA`, `CNAME`, `TXT`, `PTR`) |
| `ttl` | `INT` | Time-to-Live in seconds (Default: 60) |
| `created_at` | `DATETIME` | Creation timestamp |
| `updated_at` | `DATETIME` | Last update timestamp |

---

## 4. REST API Endpoint Specifications

### 4.1 Status & Health Check
- `GET /v1/coredns/status`
- **Response**:
  ```json
  {
    "status": "running",
    "uptime_seconds": 86400,
    "mem_bytes": 15420000,
    "listening_port": 5354,
    "forwarders": ["8.8.8.8", "1.1.1.1"],
    "total_records": 18
  }
  ```

### 4.2 Custom Static Records Management
- `GET /v1/coredns/custom-records`: List all user-defined static DNS entries.
- `POST /v1/coredns/custom-records`: Create a new static DNS record.
  ```json
  {
    "domain": "redis-cluster.gbnt",
    "ip": "192.168.252.30",
    "record_type": "A",
    "ttl": 60
  }
  ```
- `DELETE /v1/coredns/custom-records/:id`: Remove a static DNS entry.

### 4.3 Interactive DNS Playground (`Dig / Nslookup`)
- `POST /v1/coredns/dig`: Performs direct query against `127.0.0.1:5354`.
  - **Request**:
    ```json
    {
      "domain": "payment.checkout-stack.gbnt",
      "record_type": "A"
    }
    ```
  - **Response**:
    ```json
    {
      "domain": "payment.checkout-stack.gbnt",
      "record_type": "A",
      "status": "NOERROR",
      "query_time_ms": 1.25,
      "server": "127.0.0.1:5354",
      "answers": [
        {
          "name": "payment.checkout-stack.gbnt.",
          "type": "A",
          "ttl": 60,
          "data": "192.168.252.21"
        }
      ]
    }
    ```

### 4.4 Corefile Configuration
- `GET /v1/coredns/config`: Fetches raw Corefile content.
- `PUT /v1/coredns/config`: Updates Corefile and triggers `SIGHUP` reload.

---

## 5. Web UI 4-Tab Suite (`CoreDnsPage`)

1. **Tab 1: Auto-Discovered Stacks & Host-Qualified Scheme (`*.gbnt`)**: Real-time table of container IPs automatically mapped to:
   - `<node>.<service>.gbnt` and `<node>.<service>.gbnt.local` (e.g. `worker-1.caddy.gbnt`, `manager.caddy.gbnt`)
   - `<node>.<service>.<stack>.gbnt` and `<node>.<service>.<stack>.gbnt.local`
   - `<task_id>.<service>.<stack>.gbnt` and `<task_id>.<service>.<stack>.gbnt.local`
   - `<service>.<stack>.gbnt` and `<service>.<stack>.gbnt.local`
   - `<service>.gbnt` and `<service>.gbnt.local` (cluster-wide service aliases)
2. **Tab 2: Custom Static DNS Records**: Interactive table with `+ Add Static Record` modal dialog, status badges, and action buttons.
3. **Tab 3: DNS Playground (`Dig / Nslookup`)**: Terminal-like interactive console for running DNS queries, testing response latency (ms), and viewing raw DNS answers.
4. **Tab 4: Upstream Forwarders & Corefile Editor**: Quick forwarders input with Cloudflare/Google/Quad9 quick-select buttons, and raw Corefile editor.

