# CoreDNS Service Discovery & Management Suite

Gubernator features a native **CoreDNS** management engine that powers internal service discovery (`*.gbnt` and `*.gbnt.local`), custom static DNS record management (`A`, `AAAA`, `CNAME`, `TXT`, `PTR`), an interactive **DNS Dig Playground**, and upstream DNS forwarder configuration.

Every container deployed by Gubernator receives transparent `--dns <CoreDNS_IP>` injection, enabling zero-config inter-service communication across multi-node clusters.

---

## 🎯 Key Features

- **Transparent Container Service Discovery**: Automatically maps running services to `<service>.<stack>.gbnt.local`, `<service>.gbnt.local`, and `<service>.<stack>.gbnt` without manual hosts configuration.
- **Custom Static DNS Records**: Add, edit, and delete custom static DNS records (`A`, `AAAA`, `CNAME`, `TXT`, `PTR`) stored in SQLite and synced into `/etc/coredns/gubernator.hosts`.
- **Interactive DNS Playground (`Dig / Nslookup`)**: Perform real-time DNS query testing directly against `127.0.0.1:5354`, benchmark query latency in milliseconds, and inspect raw DNS answers.
- **Upstream DNS Forwarders**: Configure external DNS resolution servers with quick presets for Cloudflare (`1.1.1.1`), Google (`8.8.8.8`), Quad9 (`9.9.9.9`), or custom upstream DNS servers.
- **Raw Corefile Visual Editor**: View, edit, validate, and reload CoreDNS configurations on demand with automatic container restart.
- **4-Tab Flutter Web Suite**: Rich Material Design 3 dashboard page (`CoreDnsPage`) with real-time status gauges, record counters, search filters, and copyable `curl` testing chips.

---

## 🌐 REST API Endpoints

- `GET /v1/coredns/status`: Returns container health, uptime, listening port (`5354`), forwarders, and total DNS records count.
- `GET /v1/coredns/custom-records`: Lists all user-configured static DNS records.
- `POST /v1/coredns/custom-records`: Creates a new static DNS record and triggers CoreDNS hosts reload.
- `DELETE /v1/coredns/custom-records/:id`: Deletes a static DNS entry.
- `POST /v1/coredns/dig`: Executes a DNS query against the local CoreDNS instance.
- `GET /v1/coredns/config`: Returns raw `Corefile` content.
- `PUT /v1/coredns/config`: Overwrites `Corefile` and restarts the `gbnt-coredns` container.

---

## 🖥️ Web Dashboard Suite (`CoreDnsPage`)

1. **Tab 1: Auto-Discovered Stacks (`*.gbnt`)**: Live table of container IPs automatically mapped to `<service>.<stack>.gbnt` with copyable `curl` commands.
2. **Tab 2: Custom Static Records**: Table for managing static A/AAAA/CNAME/TXT entries with modal dialogs and live search.
3. **Tab 3: DNS Playground (`Dig / Nslookup`)**: Console for running interactive DNS resolution benchmarks.
4. **Tab 4: Upstream & Corefile**: Upstream forwarders configuration with one-click presets and raw Corefile editor.
