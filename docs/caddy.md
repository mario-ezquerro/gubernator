# Caddy Ingress Gateway & Multi-Node Reverse Proxy

Gubernator features an integrated **Caddy Ingress Subsystem** designed to provide multi-host reverse proxying, TLS termination, dynamic site block routing, and real-time observability across all nodes (Managers and Workers) in a Gubernator cluster.

---

## 🏛 Architecture & Multi-Node Proxying

In a multi-host Gubernator cluster (e.g. 3 nodes), each node runs an instance of the `gbnt-caddy` container on ports `80` and `443`, attached to the `gbnt-net` Docker network and internal **CoreDNS** resolver (`127.0.0.1:53`).

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

When you deploy a stack with an `ingress.host` constraint (or Compose service mapping), Gubernator dynamically generates and broadcasts Caddyfile blocks to all node proxies.

---

## 🔒 Automatic HTTPS & Smart Domain Management

Gubernator's Ingress engine features **Smart Domain Classification**:

### 1. Public Domains (`demo.fiware.app`, `myapp.com`)
When a public FQDN is specified in `ingress.host`:
* **Zero-Touch Let's Encrypt / ZeroSSL**: Gubernator omits `tls internal`, allowing Caddy's built-in ACME engine to automatically request, verify (HTTP-01 / TLS-ALPN-01 on ports 80/443), install, and manage official, globally trusted X.509 certificates.
* **Auto-Redirection**: Port 80 (HTTP) automatically redirects to port 443 (HTTPS).
* **Automated Renewal**: Caddy automatically renews certificates 30 days before expiration without interrupting traffic.
* **Optional ACME Email**: Supply `- ingress.email == admin@fiware.app` (or label `gbnt.ingress.email`) to receive Let's Encrypt renewal notices.

#### ☁️ Cloud Providers & 1:1 NAT (Google Cloud, AWS, Azure, Hetzner)
In cloud environments, hosts typically have a **private internal IP** (e.g. `10.128.0.2`) on their local network interface (`eth0`), while the cloud provider maps an **external public IP** (e.g. `34.120.x.x`) via 1:1 NAT or Cloud Gateway:
* **How Caddy Handles it**: ACME verification (**HTTP-01 Challenge**) does not inspect the host's internal IP. Instead, Let's Encrypt queries public DNS for your domain, contacts the external public IP on port `80`, and the cloud provider's NAT transparently forwards the challenge request to Caddy.
* **Requirements**: Ensure ports `80` and `443` are allowed in your cloud firewall (GCP VPC Firewall rules, AWS Security Groups, etc.), and that your domain's public DNS `A` record points to your cloud instance's external public IP. No manual certificate configuration or local IP binding is required.

### 2. Local Domains (`*.gbnt.local`, `*.internal`, `localhost`)
When an internal or private domain is detected:
* **Internal Root CA**: Caddy automatically applies `tls internal`, signing certificates with its internal Root CA without attempting to contact public ACME servers.
* **Root CA Trust**: Download `root.crt` from the Web UI or via API (`GET /v1/caddy/ca.crt`) to trust local HTTPS certificates in your browser.

---

## 🎨 Web UI Visualization Suite (`caddy-ui` Inspired)

Access **Caddy Ingress** in the Web Dashboard (Port 4001) to interact with 7 specialized sub-tabs:

1. **Dashboard**: Live server status across all cluster Caddies, TLS state, process info (version, uptime, memory, last reload timestamp).
2. **Route Manager**: Reverse proxy routes table, live upstream health checks, uptime %, domain search/filter, clickable links, and per-route notes.
3. **Caddyfile Editor**: Real-time Caddyfile viewer & editor, syntax validation, `caddy fmt` formatting, backup history, and 1-click rollback.
4. **TLS Certificates**: Full lifecycle management with:
   - **Multi-Node Cluster Sync**: 1-click **"Sync to All Nodes"** button (`POST /api/caddy/certs/sync`) and automatic background broadcast whenever new certificates are uploaded or rotated.
   - **X.509 Inspector**: Deep inspection of Subject, Issuer, SANs, validity dates, serial number, SHA-256 fingerprint, and key algorithm.
   - **Forced Renewal / Rotation**: 1-click certificate rotation via API and UI.
   - **Domain Cert Download**: Direct download of domain-specific `.crt` / `.pem` files.
   - **Root CA Download**: Export `root.crt` for OS trust installation.
   - **Custom TLS Upload**: Install custom commercial/corporate certificates and private keys.
   - **Orphan Pruning**: Clean up stale certificates from deleted stacks.
5. **Access Logs**: Streaming log tailing with SSE, keyword search, log level filters (`ERROR`, `WARN`, `INFO`), and JSON/TXT log export.
6. **Log Configuration**: Toggle JSON access logging per site block directly from the UI.
7. **Metrics**: Real-time request count, RPS gauge, avg latency, HTTP status code breakdown (`2xx`, `3xx`, `4xx`, `5xx`), and latency percentiles (`p50`, `p95`, `p99`) powered by Caddy's `:2019/metrics` Prometheus endpoint.

---

## 🔐 Root CA Trust Guide

To trust self-signed HTTPS certificates generated by Caddy for local domains (`.gbnt.local`):

### macOS
```bash
curl -o root.crt http://localhost:4000/v1/caddy/ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./root.crt
```

### Linux (Ubuntu/Debian)
```bash
curl -o /usr/local/share/ca-certificates/caddy-root.crt http://localhost:4000/v1/caddy/ca.crt
sudo update-ca-certificates
```

### Windows (PowerShell Admin)
```powershell
Invoke-WebRequest -Uri "http://localhost:4000/v1/caddy/ca.crt" -OutFile "root.crt"
Import-Certificate -FilePath ".\root.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

---

## 📡 REST API Reference

| Endpoint | Method | Description |
| --- | --- | --- |
| `/v1/caddy/status` | `GET` | Get process info, uptime, memory, and active instance count |
| `/v1/caddy/routes` | `GET` | Get active reverse proxy route matrix and upstream health |
| `/v1/caddy/certs` | `GET` | Get managed TLS certificates with full X.509 metadata |
| `/v1/caddy/certs/download` | `GET` | Download certificate `.crt` file for a specific domain |
| `/v1/caddy/certs/inspect` | `GET` | Inspect complete X.509 properties and SHA-256 fingerprint |
| `/v1/caddy/certs/renew` | `POST` | Force immediate renewal and rotation of a domain certificate |
| `/v1/caddy/certs/custom` | `POST` | Upload and install a custom TLS certificate and private key |
| `/v1/caddy/certs/orphaned` | `DELETE` | Prune orphaned certificates no longer in any Caddyfile |
| `/v1/caddy/ca.crt` | `GET` | Download Root CA certificate (`root.crt`) |
| `/v1/caddy/logs` | `GET` | Get container access log stream lines |
| `/v1/caddy/metrics` | `GET` | Get Prometheus request counts, RPS, and percentiles |
| `/v1/caddy/fmt` | `POST` | Format Caddyfile via `caddy fmt` |

For full specification, refer to [`SPEC-caddy.md`](https://github.com/mario-ezquerro/gubernator/blob/main/SPEC-caddy.md).
