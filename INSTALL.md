# Gubernator — Installation & Node Requirements Guide

This document covers the **hardware prerequisites**, **software dependencies**, and **SSH key provisioning** required to run a Gubernator cluster.

---

## 📋 Hardware Requirements

### Manager Node (The Senate)

The Manager node runs the API server, Web Dashboard, SQLite database, and optionally the full SRE Monitoring Stack (Prometheus, Grafana, Loki, Jaeger, cAdvisor, Promtail).

| Resource | Minimum | Recommended |
|---|---|---|
| **CPU** | 2 vCPUs | 4 vCPUs |
| **RAM** | 4 GB | **6 GB** (required when running SRE Monitor Stack) |
| **Disk** | 10 GB | 15-20 GB |
| **Network** | 1 Gbps (private network) | 1 Gbps |

> [!IMPORTANT]
> When `GBNT_MONITOR=true` is enabled, the Manager runs 7+ monitoring containers alongside the API, CoreDNS, Caddy, and Weave Scope. **6 GB RAM minimum** is essential to prevent OOM kills.

### Worker Node (The Centurion)

Worker nodes execute user containers and run a lightweight Caddy Ingress + cAdvisor agent.

| Resource | Minimum | Recommended |
|---|---|---|
| **CPU** | 1 vCPU | 2+ vCPUs |
| **RAM** | 1 GB | 2 GB (depends on workload) |
| **Disk** | 5 GB | 10 GB |
| **Network** | 100 Mbps | 1 Gbps |

---

## 🐳 Software Prerequisites

All nodes (Manager and Workers) **must** have the following installed:

### 1. Docker Engine

Docker is the container runtime that Gubernator orchestrates.

```bash
# Install Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com | sudo sh

# Add your user to the docker group (avoid sudo)
sudo usermod -aG docker $USER

# Verify installation
docker --version
docker run hello-world
```

> [!NOTE]
> Gubernator communicates with the Docker Engine via `/var/run/docker.sock`. This socket **must** be mounted when running Gubernator inside a container: `-v /var/run/docker.sock:/var/run/docker.sock`

### 2. SSH Server (Workers only)

The Manager connects to worker nodes via SSH for:
- **Remote Shell** (Terminal access from the Dashboard)
- **Node Reboot** (Reboot workers from the Dashboard)
- **Force Leave** (Drain and evacuate tasks)

```bash
# Ensure SSH server is installed and running
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

### 3. Operating System

| OS | Support Level |
|---|---|
| Ubuntu 22.04+ / 24.04 | ✅ Fully Supported |
| Debian 11+ | ✅ Fully Supported |
| Alpine Linux (Docker) | ✅ Container runtime |
| macOS (Apple Silicon) | ⚠️ Development only (Multipass VMs) |
| Raspberry Pi OS (arm64) | ✅ Supported |

---

## 🔑 SSH Key Provisioning (Automatic)

Starting with **v2.15.0**, Gubernator handles SSH key exchange automatically:

### How it works

1. **Manager Startup (`gbnt serve`):** An ED25519 SSH key pair is auto-generated at `/data/ssh/id_ed25519` (private) and `/data/ssh/id_ed25519.pub` (public) if it doesn't already exist.

2. **Worker Join (`gbnt legion join`):** The worker fetches the Manager's public key via `GET /v1/cluster/ssh-pubkey` and installs it into `/home/ubuntu/.ssh/authorized_keys` on the host.

3. **Shell/Reboot/Operations:** The Manager uses the private key at `/data/ssh/id_ed25519` to SSH into workers as `ubuntu@<worker-ip>`.

### Flow Diagram

```
Manager (gbnt serve)          Worker (gbnt legion join)
     │                              │
     ├─ Generate ED25519 keypair    │
     │  /data/ssh/id_ed25519        │
     │  /data/ssh/id_ed25519.pub    │
     │                              │
     │  GET /v1/cluster/ssh-pubkey  │
     │ ◄────────────────────────────┤
     │                              │
     │  Returns public key ─────────►
     │                              │
     │                   Install pubkey into
     │                   /home/ubuntu/.ssh/authorized_keys
     │                              │
     │  SSH ubuntu@<worker-ip> ─────►
     │  (Shell, Reboot, etc.)       │
```

### Manual SSH Key Setup (Fallback)

If the automatic key exchange fails (e.g., running outside Docker), you can manually set it up:

```bash
# On the Manager host/container, generate a key:
ssh-keygen -t ed25519 -f /data/ssh/id_ed25519 -N "" -C "gubernator-manager"

# Copy the public key to each worker:
ssh-copy-id -i /data/ssh/id_ed25519.pub ubuntu@<WORKER-IP>

# Test the connection:
ssh -i /data/ssh/id_ed25519 ubuntu@<WORKER-IP> "echo OK"
```

### Docker Volume Persistence

The SSH keys live in `/data/ssh/` which is inside the `/data` volume. **Always mount a persistent volume** to avoid regenerating keys on restart:

```bash
docker run -d --name gbnt-manager \
  -v gubernator-data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  marioezquerro/gubernator:latest serve
```

---

## 🚀 Quick Start: 3-Node Cluster (Multipass)

### 1. Create VMs

```bash
# Manager (6GB RAM, 4 CPUs, 15GB disk)
multipass launch 24.04 -n gbnt-manager -c 4 -m 6G -d 15G

# Workers (2GB RAM, 2 CPUs, 10GB disk each)
multipass launch 24.04 -n gbnt-worker1 -c 2 -m 2G -d 10G
multipass launch 24.04 -n gbnt-worker2 -c 2 -m 2G -d 10G
```

### 2. Install Docker on all VMs

```bash
for vm in gbnt-manager gbnt-worker1 gbnt-worker2; do
  multipass exec $vm -- bash -c "curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker ubuntu"
done
```

### 3. Deploy Manager

```bash
multipass exec gbnt-manager -- sudo docker run -d \
  --name gbnt-manager \
  --network host \
  --restart unless-stopped \
  -e GBNT_MONITOR=true \
  -e GBNT_WEB=true \
  -e GBNT_WEB_USER=admin \
  -e GBNT_WEB_PASSWORD=admin \
  -v /data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  marioezquerro/gubernator:latest serve
```

### 4. Get Tokens

```bash
multipass exec gbnt-manager -- sudo docker exec gbnt-manager gbnt legion info
```

### 5. Join Workers

You can join workers using any of the following:

#### Option A: One-Liner Script (Fastest)
```bash
multipass exec gbnt-worker1 -- bash -c "curl -fsSL http://<MANAGER_IP>:4001/api/node/join.sh | sudo bash -s -- --manager http://<MANAGER_IP>:4000 --token <JOIN_TOKEN> --api-token <API_TOKEN>"
```

#### Option B: Docker Container
```bash
# Replace <JOIN_TOKEN>, <API_TOKEN>, and <MANAGER_IP> with actual values
multipass exec gbnt-worker1 -- sudo docker run -d \
  --name gbnt-worker \
  --network host \
  --restart unless-stopped \
  -v /data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  marioezquerro/gubernator:latest \
  legion join --token <JOIN_TOKEN> --api-token <API_TOKEN> --manager http://<MANAGER_IP>:4000
```

#### Option C: Web Dashboard
Open `http://<MANAGER_IP>:4001` ➔ **Centurions [Host]** ➔ **Add Centurion** and use the **Quick Join** or **Remote SSH Provisioning** wizard with live console feedback.
```

### 6. Access Dashboard

Open `http://<MANAGER_IP>:4001` in your browser (credentials: `admin`/`admin`).

---

## 🔧 Environment Variables Reference

| Variable | Default | Description |
|---|---|---|
| `GBNT_DATA_DIR` | `/data` | Directory for SQLite DB and SSH keys |
| `GBNT_API_TOKEN` | *(auto-generated)* | Override Bearer token for REST API |
| `GBNT_WEB` | `false` | Enable Flutter Web Dashboard (port 4001) |
| `GBNT_WEB_USER` | — | Username for Web Dashboard Basic Auth |
| `GBNT_WEB_PASSWORD` | — | Password for Web Dashboard Basic Auth |
| `GBNT_MONITOR` | `false` | Auto-deploy SRE monitoring stack on startup |
| `GBNT_DNS_FORWARDERS` | `8.8.8.8 1.1.1.1` | External DNS servers for CoreDNS |

---

## 🛡️ Ports Reference

| Port | Service | Security |
|---|---|---|
| **4000** | REST API (CLI) | Bearer Token (`GBNT_API_TOKEN`) |
| **4001** | Web Dashboard (Flutter) | Basic Auth (`GBNT_WEB_USER`/`GBNT_WEB_PASSWORD`) |
| **4002** | Telemetry, Swagger, Healthcheck | Open (internal monitoring) |
| **22** | SSH (Workers) | ED25519 public key authentication |
| **9090** | Prometheus | Internal (Manager only) |
| **3000** | Grafana | Internal (Manager only) |
| **3100** | Loki | Internal (Manager only) |
| **4040** | Weave Scope | Internal (Manager only) |
