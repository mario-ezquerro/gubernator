# Caddy Ingress Threat Shield & Web Application Firewall (WAF)

Gubernator integrates an **air-gapped, zero-dependency Web Application Firewall (WAF) & Threat Shield** directly into the native Caddy Ingress reverse proxy gateway.

Designed with a **hybrid security model**, Threat Shield can be controlled **declaratively via Docker Compose labels** or **manually ("a mano")** per route or globally through the Flutter Web Dashboard, CLI, and REST API.

---

## 🛡️ Core Capabilities

* **Dual Management Control**:
  * **Declarative (Compose)**: Specify `gbnt.waf.enabled=true` and `gbnt.waf.mode=enforce|detection` in your stack `docker-compose.yml`.
  * **Manual ("A Mano")**: Toggle WAF on or off instantly with 1 click from the Web UI or via `gbnt caddy waf enable/disable <host>`. Manual overrides take precedence over Compose labels.
* **100% Native Caddy Architecture**: Uses Caddy's high-performance native request matchers (`vars_regexp`, `header_regexp`, `path_regexp`, `remote_ip`) without requiring Cgo, external daemon sidecars, or dynamic binary compilation.
* **Dual Operating Modes**:
  * **Enforce (Block 403)**: Blocks malicious requests immediately at the edge and returns a detailed `403 Forbidden` response.
  * **Detection (Alert Only)**: Permissive mode that passes traffic downstream while annotating responses with `X-Threat-Shield-Warning` and recording security events in the audit trail.
* **Real-Time SIEM & Audit Trail**: Every intercepted probe is recorded in the SQLite database with client IP, timestamp, target URI, attack vector, rule ID, and action taken.
* **Built-in Attack Simulator**: One-click penetration test probe tool built into the Web UI and CLI to verify WAF interception rules on any cluster route.

---

## 🎯 Protection Vectors (OWASP Top 10)

| Vector | Rule ID | Threat Description | Detection Pattern |
|---|---|---|---|
| **SQL Injection (SQLi)** | `WAF003` | Unauthorized database queries, UNION SELECT, timing attacks, data dumping | `union select`, `select ... from`, `sleep()`, `benchmark()`, `information_schema`, `or 1=1`, `--`, `;drop table` |
| **Cross-Site Scripting (XSS)** | `WAF004` | Malicious JavaScript injection, stolen session cookies, DOM poisoning | `<script>`, `javascript:`, `onerror=`, `onload=`, `document.cookie`, `<img src=x>` |
| **Remote Code Execution (RCE)** | `WAF005` | Shell command injection, Log4j / Log4Shell exploitation, malicious binaries | `${jndi:ldap`, `/bin/sh`, `/bin/bash`, `powershell`, `cmd.exe`, `wget http`, `curl http` |
| **Path Traversal & LFI / RFI** | `WAF002` | Local File Inclusion, access to system files outside web root | `../`, `..\`, `/etc/passwd`, `/proc/self`, `win.ini`, `boot.ini` |
| **Scanners & Bot Probes** | `WAF001` | Automated vulnerability scanners, brute-force recon tools | `sqlmap`, `nikto`, `w3af`, `acunetix`, `nessus`, `gobuster`, `dirbuster`, `masscan`, `nmap`, `wpscan` |
| **IP Blacklist & Whitelist** | `WAF006` | Edge IP / CIDR blocklist with private subnet whitelist | Exact IP match or CIDR subnet block (`remote_ip`) |

---

## 📋 Declarative Compose Usage

You can enable and configure Threat Shield directly in any stack's `docker-compose.yml`:

```yaml
version: '3.8'
services:
  webapp:
    image: nginx:alpine
    deploy:
      placement:
        constraints:
          - "ingress.host=app.gbnt.local"
          - "gbnt.waf.enabled=true"
          - "gbnt.waf.mode=enforce"
```

### Supported Compose Constraints

* `gbnt.waf.enabled=true|false` (or `ingress.waf.enabled`): Enable or disable WAF for this service route.
* `gbnt.waf.mode=enforce|detection` (or `ingress.waf.mode`): Set route-specific operating mode.

---

## 🖐️ Manual Control ("A Mano")

Whenever a developer or security operator needs to override Compose settings or urgently protect a route:

### 1. Via Flutter Web Dashboard

1. Navigate to **Caddy Ingress** in the left sidebar.
2. In **Tab 2 (Routes)**:
   * Review the **THREAT SHIELD (WAF)** column.
   * View the active status badge (`🟢 ENFORCE [a mano]`, `🟡 DETECT`, or `⚪ OFF`).
   * Click the **Power / Play** button to toggle WAF ON or OFF instantly for that specific route.
3. In **Tab 8 (WAF & Threat Shield)**:
   * Toggle the global cluster-wide master switch.
   * Switch between **Enforce** and **Detection** modes.
   * Select Paranoia Level (1 to 4).
   * Toggle individual attack vectors (SQLi, XSS, RCE, LFI, Scanners).
   * Manage the IP Blacklist and Whitelist.
   * Run live attack probes with the built-in Attack Simulator.
   * Review the real-time Intercepted Threat Events Stream.

---

## 💻 CLI Commands (`gbnt caddy waf`)

Gubernator provides complete CLI parity for WAF management:

### 1. Display Status & Protected Routes

```bash
gbnt caddy waf status
```

**Output:**
```text
🛡️  Gubernator Caddy Threat Shield & WAF Engine
==================================================
Status:             🟢 ACTIVE (ENFORCING)
Default Mode:       enforce
Paranoia Level:     1
Requests Evaluated: 142
Blocked Attacks:    8
Blacklisted IPs:    2
--------------------------------------------------
Threat Vectors Protected:
  • SQLi (SQL Injection):       true
  • XSS (Cross-Site Scripting): true
  • RCE / Log4j:                true
  • Path Traversal / LFI:       true
  • Scanners & Automated Bots:  true
--------------------------------------------------

Per-Route Overrides ("A Mano" / Compose):
HOST                                STATUS       MODE         ORIGIN      
---------------------------------------------------------------------------
app.gbnt.local                      ENABLED      enforce      manual      
api.example.com                     DISABLED     inherit      manual      
```

### 2. Enable or Disable WAF

```bash
# Enable globally across all ingress routes
gbnt caddy waf enable

# Enable for a specific route ("a mano")
gbnt caddy waf enable app.gbnt.local --mode enforce

# Disable for a specific route ("a mano")
gbnt caddy waf disable app.gbnt.local

# Disable globally
gbnt caddy waf disable
```

### 3. Change Operating Mode

```bash
# Set global mode to detection (audit without blocking)
gbnt caddy waf mode detection

# Set global mode to enforce (active blocking with 403)
gbnt caddy waf mode enforce

# Set mode for a specific route
gbnt caddy waf mode detection --host app.gbnt.local
```

### 4. IP Blacklisting & Whitelisting

```bash
# Block an IP address or CIDR subnet
gbnt caddy waf ip block 198.51.100.42 "Repeated automated SQLi attacks"

# Unblock an IP
gbnt caddy waf ip unblock 198.51.100.42
```

### 5. Inspect Threat Events Stream

```bash
# View recent intercepted attacks
gbnt caddy waf events --limit 20

# Filter by attack vector
gbnt caddy waf events --type SQLI

# Filter by target hostname
gbnt caddy waf events --host app.gbnt.local
```

### 6. Simulate Attack Probes (Penetration Test)

```bash
# Test SQL injection probe
gbnt caddy waf test app.gbnt.local --vector SQLI

# Test Cross-Site Scripting
gbnt caddy waf test app.gbnt.local --vector XSS

# Test Remote Code Execution (Log4j)
gbnt caddy waf test app.gbnt.local --vector RCE

# Test Path Traversal
gbnt caddy waf test app.gbnt.local --vector LFI

# Test Malicious Scanner User-Agent
gbnt caddy waf test app.gbnt.local --vector SCANNER
```

---

## 🌐 REST API Reference

| Method | Endpoint | Description | Auth Tier |
|---|---|---|---|
| `GET` | `/v1/caddy/waf/config` | Fetch global Threat Shield configuration | Admin / Operator / Readonly |
| `POST` | `/v1/caddy/waf/config` | Update global Threat Shield configuration | Admin / Operator |
| `GET` | `/v1/caddy/waf/routes` | List per-route WAF overrides | Admin / Operator / Readonly |
| `POST` | `/v1/caddy/waf/routes/toggle` | Toggle WAF state for a specific route ("a mano") | Admin / Operator |
| `DELETE` | `/v1/caddy/waf/routes/:host` | Clear route override and restore cluster default | Admin / Operator |
| `GET` | `/v1/caddy/waf/events` | List intercepted threat events (supports `?limit=`, `?type=`, `?host=`) | Admin / Operator / Readonly |
| `GET` | `/v1/caddy/waf/stats` | Fetch aggregate attack counts and metrics | Admin / Operator / Readonly |
| `POST` | `/v1/caddy/waf/ip/block` | Add IP or CIDR to blacklist | Admin / Operator |
| `POST` | `/v1/caddy/waf/ip/unblock` | Remove IP from blacklist | Admin / Operator |
| `POST` | `/v1/caddy/waf/test` | Simulate a threat attack probe | Admin / Operator |

---

## 🔄 Zero-Downtime Hot Reload

Whenever a WAF rule, per-route toggle, or IP blacklist is modified:
1. Gubernator updates the SQLite state database (`managed_waf_configs`, `managed_route_wafs`).
2. The internal hook `OnWAFConfigUpdatedHook` triggers `aqueducts.GenerateCaddyfile()`.
3. The Caddyfile is atomically rewritten in `/var/lib/caddy/Caddyfile`.
4. Caddy executes an internal configuration reload via `caddy reload --config /etc/caddy/Caddyfile` without dropping existing HTTP connections.
