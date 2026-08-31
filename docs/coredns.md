# CoreDNS Service Discovery & Management Suite

Gubernator features a native **CoreDNS** management engine that powers internal service discovery (`*.<cluster_domain>` and `*.gbnt.local`), dynamic base domain configuration (`GBNT_CLUSTER_DOMAIN`), custom static DNS record management (`A`, `AAAA`, `CNAME`, `TXT`, `PTR`), an interactive **DNS Dig Playground**, and upstream DNS forwarder configuration.

Every container deployed by Gubernator receives transparent `--dns <CoreDNS_IP>` injection, enabling zero-config inter-service communication across multi-node clusters.

---

## 🎯 Key Features

- **Dynamic Enterprise Cluster Base Domain (`GBNT_CLUSTER_DOMAIN`)**: Configurable base domain suffix (e.g. `acme.corp`, `internal.banco.es`, `dev.company.local`, or `gbnt.local`) persisted centrally in SQLite (`ClusterConfig.ClusterDomain`) and synchronized across all Centurions.
- **Streamlined Host-Qualified DNS Scheme (`<node>.<service>.<cluster_domain>`)**: Eliminates multi-node service collisions by cleanly mapping system and infrastructure containers strictly to their host (e.g. `manager.caddy.acme.corp`, `node-gbnt-worker1.caddy.acme.corp`, `manager.loki.acme.corp`).
- **Stack-Scoped Isolation for Applications (`<service>.<stack>.<cluster_domain>`)**: User application containers are accessible via `<service>.<stack>.<cluster_domain>` (e.g. `app.wordpress.acme.corp`, `db.wordpress.acme.corp`) and `<node>.<service>.<cluster_domain>`.
- **Zero-Spam & Zero-Collision Architecture**: Streamlined generation prevents duplicate un-scoped records across multi-worker deployments, reducing DNS entries per container to 2–4 pristine records.
- **RFC 1123 DNS Label Sanitization**: Automatically normalizes stack and task identifiers (converting brackets, parentheses, and spaces to hyphens) into strictly valid DNS domain labels.
- **Custom Static DNS Records**: Add, edit, and delete custom static DNS records (`A`, `AAAA`, `CNAME`, `TXT`, `PTR`) stored in SQLite and synced into `/etc/coredns/gubernator.hosts`.
- **Interactive DNS Playground (`Dig / Nslookup`)**: Perform real-time DNS query testing directly against `127.0.0.1:5354`, benchmark query latency in milliseconds, and inspect raw DNS answers.
- **Upstream DNS Forwarders**: Configure external DNS resolution servers with quick presets for Cloudflare (`1.1.1.1`), Google (`8.8.8.8`), Quad9 (`9.9.9.9`), or custom upstream DNS servers.
- **Raw Corefile Visual Editor & Hot Reload**: View, edit, validate, and reload CoreDNS configurations on demand with zero downtime via SIGHUP.
- **5-KPI Dashboard Suite (`CoreDnsPage`)**: Rich Material Design 3 dashboard page with live server status, cluster base domain card with edit modal, listener port, record counters, and search filters.

---

## 🌐 Dynamic Base Domain Configuration

You can configure the base cluster domain at startup using environment variables:

```bash
# Set custom corporate domain at initial boot
export GBNT_CLUSTER_DOMAIN="acme.corp"
# or
export GBNT_DOMAIN="internal.banco.es"
```

Or modify it in real-time via REST API or the Web Dashboard:

```bash
# Query active cluster base domain
curl -H "Authorization: Bearer $GBNT_API_TOKEN" \
     http://localhost:4000/v1/cluster/domain

# Update cluster base domain (automatically rewrites Corefile and reloads CoreDNS)
curl -X PUT -H "Authorization: Bearer $GBNT_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"cluster_domain": "corp.internal"}' \
     http://localhost:4000/v1/cluster/domain
```

---

## 🌐 REST API Endpoints

- `GET /v1/cluster/domain`: Returns the active cluster base domain (`{"cluster_domain": "acme.corp"}`).
- `PUT /v1/cluster/domain`: Updates cluster base domain, updates SQLite, rewrites Corefile, regenerates `gubernator.hosts`, and triggers CoreDNS reload.
- `GET /v1/coredns/status`: Returns container health, uptime, listening port (`5354`), forwarders, and total DNS records count.
- `GET /v1/coredns/custom-records`: Lists all user-configured static DNS records.
- `POST /v1/coredns/custom-records`: Creates a new static DNS record and triggers CoreDNS hosts reload.
- `DELETE /v1/coredns/custom-records/:id`: Deletes a static DNS entry.
- `POST /v1/coredns/dig`: Executes a DNS query against the local CoreDNS instance.
- `GET /v1/coredns/config`: Returns raw `Corefile` content.
- `PUT /v1/coredns/config`: Overwrites `Corefile` and restarts the `gbnt-coredns` container.

---

## 🖥️ Web Dashboard Suite (`CoreDnsPage`)

1. **KPI Summary Cards**:
   - **SERVER STATUS**: Real-time status indicator (`RUNNING` / `STOPPED`).
   - **CLUSTER DOMAIN**: Active base domain with an **Edit Modal Dialog** for changing the domain on the fly.
   - **LISTENER PORT**: Host & container DNS ports (`53 / 5354`).
   - **TOTAL DNS RECORDS**: Total active auto-discovered and custom static DNS records.
   - **FORWARDERS**: Count of active upstream resolvers (`Cloudflare`, `Google`, etc.).
2. **Tab 1: Auto-Discovered Stacks & Host-Qualified Scheme (`*.<cluster_domain>`)**: Live table of container IPs mapped to `<node>.<service>.<cluster_domain>` and `<service>.<stack>.<cluster_domain>` with copyable `curl` commands.
3. **Tab 2: Custom Static Records**: Table for managing static A/AAAA/CNAME/TXT entries with modal dialogs and live search.
4. **Tab 3: DNS Playground (`Dig / Nslookup`)**: Console for running interactive DNS resolution benchmarks.
5. **Tab 4: Upstream & Corefile**: Upstream forwarders configuration with one-click presets and raw Corefile editor.


