# Multi-Host Cluster Setup (The Legion)

This guide walks you through setting up a multi-host Gubernator cluster ("The Legion") consisting of one Manager node and multiple Worker nodes. 

---

## 🏛 Cluster Architecture Overview

Gubernator uses a centralized manager model with worker agents:
1. **Manager Node**: Runs the REST API (`gbnt serve`), stores cluster state in SQLite, runs the web dashboard, manages Ingress/DNS (Caddy & CoreDNS), and schedules tasks.
2. **Worker Nodes**: Run a lightweight executor loop (`gbnt legion join`) that polls the Manager for tasks, pulls Docker images, executes containers locally, and reports back task status and heartbeats.

---

## 🖥 Server & VM Requirements

Before setting up the cluster, ensure your hosts meet the following minimum specs:

### Operating System
* **Ubuntu 22.04 LTS / 24.04 LTS / 26.04 LTS** (Any modern Debian-based Linux distribution).
* Support for both **x86_64 (AMD64)** and **ARM64** architectures.

### System Resources
* **Manager Node**: Minimum 1 CPU, 1.5 GB RAM (recommended for database and native compilation/SRE stack), and 15 GB disk space.
* **Worker Nodes**: Minimum 1 CPU, 1 GB RAM, and 10 GB disk space.

### Networking
* All hosts must have IP connectivity on a private subnet (e.g. `192.168.x.x` or `10.x.x.x`).
* **Port openings required**:
  * **Port 4000**: Manager API REST (accessible by CLI and Worker nodes).
  * **Port 4001**: Web UI Dashboard (optional, accessible by operator/browser).
  * **Port 4002**: Telemetry, Swagger, and Health metrics.
  * **Port 53 / 5354**: CoreDNS internally.
  * **Port 80 / 443**: Caddy Ingress.
  * **Ports 3000 / 9090 / 9100 / 3100 / 8081 / 4317 / 4318 / 16686**: SRE monitoring stack (Grafana, Prometheus, Node Exporter, Loki, cAdvisor, Jaeger OTLP & UI).

---

## 🐋 1. Install Docker on All Nodes

Every node in the cluster must have Docker running. Execute the following commands on **all hosts** to install Docker and allow the default user (e.g. `ubuntu`) to run Docker commands without root privileges:

```bash
# Update package list and install Docker
sudo apt-get update
sudo apt-get install -y docker.io

# Enable and start the Docker service
sudo systemctl enable --now docker

# Add your user to the docker group (e.g. 'ubuntu')
sudo usermod -aG docker ubuntu
```

> [!NOTE]
> For the group changes to take effect without logging out, you can run commands prefixed with `sg docker -c "your-command"`.

---

## 🏗 2. Compile and Deploy the Binary

Compile the `gbnt` binary for your target node architecture. If your target hosts run Linux ARM64 (e.g. Multipass on Apple Silicon), cross-compile using:

```bash
GOOS=linux GOARCH=arm64 go build -ldflags "-X main.version=$(cat VERSION)" -o gbnt-linux-arm64 ./cmd/gbnt
```

Copy the compiled binary to `/usr/local/bin/gbnt` or `/home/ubuntu/gbnt` on all nodes:

```bash
# Transfer the binary to your nodes
multipass transfer gbnt-linux-arm64 gbnt-manager:/home/ubuntu/gbnt
multipass transfer gbnt-linux-arm64 gbnt-worker1:/home/ubuntu/gbnt
multipass transfer gbnt-linux-arm64 gbnt-worker2:/home/ubuntu/gbnt
```

---

## 🏛 3. Initialize the Manager Node

On the designated **Manager node**, create the data directory for the SQLite database and start the Gubernator service in the background:

```bash
# Create persistent data directory
mkdir -p /home/ubuntu/data

# Start the Manager service
GBNT_API_TOKEN=my-gubernator-api-token \
GBNT_HOST_IP=<MANAGER-IP> \
GBNT_DATA_DIR=/home/ubuntu/data \
GBNT_WEB=true \
GBNT_WEB_USER=admin \
GBNT_WEB_PASSWORD=admin \
GBNT_MONITOR=true \
nohup /home/ubuntu/gbnt serve > /home/ubuntu/manager.log 2>&1 &
```

### Environment Variables Explained:
* `GBNT_API_TOKEN`: The bearer token that CLI and Workers use to authenticate.
* `GBNT_HOST_IP`: The IP address of the manager node that workers will connect to.
* `GBNT_WEB`: Enables the Web UI Dashboard on port `4001`.
* `GBNT_WEB_USER` & `GBNT_WEB_PASSWORD`: Credentials to access the Web UI and the Grafana SSO proxy.
* `GBNT_MONITOR=true`: Auto-deploys the SRE Observability stack (Prometheus, Grafana, Loki, cAdvisor, Node Exporter, Promtail, Jaeger).

---

## 📋 4. Retrieve the Cluster Join Token

Generate the cluster join token from the Manager node:

```bash
# Run on the Manager Node
/home/ubuntu/gbnt legion join-token
```

Output:
```text
To add a worker to this legion, run the following command:

    gbnt legion join \
        --token d04de109ec96411d1fd7672e04725244 \
        --api-token <API_TOKEN> \
        --manager <MANAGER-IP>:4000
```

---

## 💓 5. Universal Centurion Worker Onboarding Suite

Gubernator provides **3 flexible methods** to join Worker nodes (*Centurions*) into the cluster, accessible directly from the Web Dashboard (**Centurions [Host] ➔ Add Centurion**) or via CLI and automated scripts:

### ⚡ Method A: Quick Join (Copy & Paste Commands)
*Best for fast setup, cloud VMs, or hosts behind NAT/firewalls (no SSH configuration needed).*

Open a terminal on your target worker machine and paste any of the following commands:

#### Option 1: One-Liner Automated Installer (Recommended)
Automatically installs Docker CE if missing, configures systemd persistence, and starts the Centurion worker agent:
```bash
curl -fsSL http://<MANAGER-IP>:4001/api/node/join.sh | sudo bash -s -- \
    --manager http://<MANAGER-IP>:4000 \
    --token <JOIN_TOKEN> \
    --api-token <API_TOKEN>
```

#### Option 2: Docker Container (Native Engine)
Runs the Centurion worker agent inside an isolated container with host network permissions:
```bash
sudo docker run -d --name gbnt-worker \
    --network host \
    --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /data:/data \
    marioezquerro/gubernator:latest legion join \
    --token <JOIN_TOKEN> \
    --manager http://<MANAGER-IP>:4000 \
    --api-token <API_TOKEN>
```

#### Option 3: Standalone Gubernator Binary
```bash
sudo gbnt legion join \
    --token <JOIN_TOKEN> \
    --manager http://<MANAGER-IP>:4000 \
    --api-token <API_TOKEN>
```

---

### 🚀 Method B: Remote SSH Provisioning + Live Terminal Console
*Best when you want the Manager to connect over SSH and bootstrap the remote host with zero manual work on the worker machine.*

1. Open the Web Dashboard at `http://<MANAGER-IP>:4001` and navigate to **Centurions [Host]**.
2. Click **Add Centurion**.
3. Select the **🚀 Remote SSH Provision** tab.
4. Fill in:
   * **Host IP / FQDN**: `192.168.252.34`
   * **SSH Port**: `22`
   * **SSH Username**: `ubuntu` / `root`
   * **Authentication Method**:
     * 🔑 **Password**: Enter password (used for SSH login & sudo elevation).
     * 🛡️ **Private Key (.pem)**: Paste your OpenSSH RSA/ED25519 private key.
     * 👑 **Manager SSH Key**: Uses the Manager's internal SSH key (`/data/ssh/id_ed25519.pub`).
   * **Auto-deploy System Stacks**: Automatically deploys Caddy Ingress (`CORE-GBNT`) and Prometheus Monitoring agents (`[SRE] Monitor`).
5. Click **Start Remote SSH Provisioning**.
6. The modal transforms into a **Live Monospace Terminal Console** showing step-by-step progress:
   ```text
   [SSH Connection]       Connecting to 192.168.252.34:22 as user 'ubuntu'...
   [SSH Handshake]        SSH session established securely.
   [Hardware Discovery]   Detected hostname 'gbnt-worker3', 2 CPU cores, 1955 MB RAM.
   [Cluster Registry]     Registered Centurion 'node-gbnt-worker3' into database.
   [Docker Engine]        Docker CE runtime is installed and operational.
   [Agent Deployment]     Gubernator Centurion worker container deployed and running.
   [System Stacks]        Bootstrapping CORE-GBNT (Caddy) and SRE Monitor services...
   [Aqueducts & Telemetry] Updating CoreDNS routing and Prometheus metric scraping targets...
   [Complete]             Centurion 'node-gbnt-worker3' successfully provisioned and online!
   🎉 SUCCESS: Centurion worker host is online and active in cluster!
   ```

---

### ☁️ Method C: Cloud-Init & Infrastructure as Code (IaC)
*Best for automated provisioning with Proxmox VE, OpenStack, AWS EC2 UserData, GCP, Hetzner Cloud, or Terraform.*

Copy the following `#cloud-config` template into your VM UserData configuration:

```yaml
#cloud-config
package_upgrade: true
packages:
  - curl
  - docker.io
runcmd:
  - systemctl enable --now docker
  - sudo docker run -d --name gbnt-worker --network host --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v /data:/data marioezquerro/gubernator:latest legion join --token <JOIN_TOKEN> --manager http://<MANAGER-IP>:4000 --api-token <API_TOKEN>
```

---

## 📊 6. Verify and Connect

### Verify Nodes from Local CLI
Configure your local CLI on the host machine to point to the remote Manager:

```bash
# Configure context
gbnt config add-context remote-multipass \
    --server http://<MANAGER-IP>:4000 \
    --token my-gubernator-api-token

# Set active context
gbnt config use-context remote-multipass

# List nodes
gbnt node ls
```

Output:
```text
ID                   IP              ROLE      STATUS   
node-local-manager   192.168.252.5   manager   active   
node-gbnt-worker1    192.168.252.6   worker    active   
node-gbnt-worker2    192.168.252.7   worker    active   
```

### Accessing Web Interfaces
* **Gubernator Web UI**: `http://<MANAGER-IP>:4001` (User: `admin` / Password: `admin`)
* **Grafana (Observability & Logs)**: `http://<MANAGER-IP>:4001/grafana/` (Auto-login with Dashboard credentials)
* **Prometheus Dashboard**: `http://<MANAGER-IP>:9090`
* **cAdvisor Dashboard**: `http://<MANAGER-IP>:8081`
* **Node Exporter**: `http://<MANAGER-IP>:9100/metrics`

---

## 🔐 7. Token Mismatch Detection & SSH Auto-Sync

When rotating the cluster's `GBNT_API_TOKEN` or when worker daemons attempt to heartbeat with an outdated token:
1. **Automatic Detection**: The Manager's authentication watchdog detects failed 401 attempts originating from registered worker IPs.
2. **Visual Warning Badge**: The Web Dashboard flags the node with an orange **`Token Mismatch`** badge in the Centurions table.
3. **Interactive Sync Dialog**:
   - Activating the node or clicking the badge opens the **Token Desincronizado** dialog.
   - Displays the exact `gbnt legion join` update command with current active tokens.
   - Provides a **"Auto-Sync vía SSH"** button that executes `POST /api/node/:id/sync-token`, updating the worker daemon and restarting the container remotely over SSH without manual terminal intervention.

---

## 🌐 8. Enterprise Base Domain Configuration (`GBNT_CLUSTER_DOMAIN`)

In enterprise environments, organizations typically require internal containers and services to resolve under their corporate DNS namespace (e.g. `acme.corp`, `internal.banco.es`, `dev.company.local`, or `cluster.internal`):

```bash
# Initialize Manager with custom enterprise base domain
GBNT_CLUSTER_DOMAIN=acme.corp gbnt serve
```

When configured:
* All container hostnames automatically resolve as `<node>.<service>.acme.corp` (e.g. `node-gbnt-worker1.caddy.acme.corp`, `manager.loki.acme.corp`).
* Stack services communicate using `<service>.<stack>.acme.corp` (e.g. `app.wordpress.acme.corp`).
* CoreDNS automatically creates and serves DNS zone blocks for `acme.corp` and `gbnt.local`.
* The base domain can be updated on the fly via REST API (`PUT /v1/cluster/domain`) or the Web Dashboard CoreDNS Suite with zero downtime.


