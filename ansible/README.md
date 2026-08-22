# 🏛️ Gubernator Ansible Automation & Cluster Provisioning

Automated Ansible playbooks and roles to prepare bare-metal or virtualized Linux hosts (Debian/Ubuntu, RHEL/Rocky/AlmaLinux/Fedora) and provision a high-performance **Gubernator** cluster with **Docker CE**, **Weave Net / Wave Scope** network topology visualization, and the **SRE Observability Stack** (Grafana, Loki, Prometheus, Jaeger, cAdvisor).

---

## 📋 Features

* **Multi-Distribution Support**:
  * 🐧 **Debian Family**: Ubuntu 20.04, 22.04, 24.04 LTS, Debian 11/12.
  * 🎩 **Red Hat Family**: RHEL 8/9, Rocky Linux 8/9, AlmaLinux 8/9, CentOS Stream, Fedora.
* **Kernel & System Hardening**:
  * Loads container & overlay network kernel modules (`overlay`, `br_netfilter`, `ip_tables`, `nf_conntrack`).
  * Applies optimized `sysctl` parameters (`net.bridge.bridge-nf-call-iptables = 1`, `net.ipv4.ip_forward = 1`, inotify watch increases).
  * Configures firewall rules (UFW / Firewalld) for API, Web Dashboard, Caddy Ingress, CoreDNS, and Wave Scope.
* **Docker CE Automation**:
  * Configures official Docker GPG keys and repositories.
  * Installs Docker CE, CLI, Containerd, Buildx, and Compose plugin.
  * Provisions `/etc/docker/daemon.json` with log rotation (`json-file`, `10m`) and live-restore.
  * Adds the SSH/deployment user to the `docker` group.
* **Automated Gubernator Cluster Setup**:
  * Downloads official release binary (`gbnt`) matching the target CPU architecture (`amd64` / `arm64`).
  * Configures and starts systemd units (`gbnt-manager.service` and `gbnt-worker.service`).
  * Automatically retrieves the join token on Manager and registers Centurion Workers.
* **Wave Scope Topology Probe**:
  * Deploys containerized Weave Scope probe & app (`marioezquerro/scope:latest`) with host PID/network sharing.
* **SRE Observability**:
  * Triggers `gbnt monitor init` on the Manager for one-command deployment of Grafana (`:3000`), Loki (`:3100`), Prometheus (`:9090`), and Jaeger (`:16686`).

---

## 📂 Directory Layout

```text
ansible/
├── ansible.cfg                 # Optimized Ansible defaults (pipelining, forks, yaml callback)
├── inventory.example.ini       # Sample inventory file (INI format)
├── inventory.example.yml       # Sample inventory file (YAML format)
├── site.yml                    # Master execution playbook
├── group_vars/
│   ├── all.yml                 # Global cluster settings (version, ports, docker tuning)
│   ├── manager.yml             # Manager-specific port mappings (API, UI, Caddy, CoreDNS)
│   └── workers.yml             # Worker-specific configurations
├── roles/
│   ├── common/                 # OS packages, kernel modules, sysctl & firewall rules
│   ├── docker/                 # Multi-distro Docker CE engine & daemon.json setup
│   ├── gubernator/             # Binary deployment, systemd units & cluster registration
│   ├── wave_scope/             # Wave Scope topology probe & app container
│   └── sre_monitoring/         # SRE Observability stack initialization
└── README.md                   # This documentation guide
```

---

## 🚀 Quick Start in 3 Steps

### 1. Prerequisites
Ensure Ansible (2.12+) is installed on your workstation:
```bash
# macOS
brew install ansible

# Ubuntu / Debian
sudo apt update && sudo apt install -y ansible

# Fedora / RHEL
sudo dnf install -y ansible
```

### 2. Configure Your Inventory
Copy `inventory.example.ini` to `inventory.ini` and set your node IP addresses and SSH credentials:

```ini
[manager]
gbnt-manager ansible_host=192.168.1.10 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[workers]
gbnt-worker1 ansible_host=192.168.1.11 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa gbnt_zone=europe-west1
gbnt-worker2 ansible_host=192.168.1.12 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa gbnt_zone=europe-west2
gbnt-worker3 ansible_host=192.168.1.13 ansible_user=rocky  ansible_ssh_private_key_file=~/.ssh/id_rsa gbnt_gpu=nvidia

[cluster:children]
manager
workers
```

### 3. Run the Playbook
Execute the complete end-to-end provisioning:

```bash
cd ansible
ansible-playbook -i inventory.ini site.yml
```

---

## 🏷️ Selective Execution with Tags

You can run specific parts of the provisioning using Ansible tags:

| Tag | Purpose |
| :--- | :--- |
| `common` / `bootstrap` | Install dependencies, load kernel modules, tune sysctl, configure firewall |
| `docker` | Install and configure Docker CE engine and `daemon.json` |
| `gubernator` | Deploy `gbnt` binary, start Manager and register Workers |
| `manager` | Deploy only Manager systemd service and token generation |
| `workers` | Deploy only Worker systemd services and cluster join |
| `wave_scope` | Deploy Wave Scope topology container |
| `monitoring` / `sre` | Deploy Grafana, Loki, Prometheus, cAdvisor, and Jaeger |
| `glusterfs` / `storage` | Deploy 3-way replicated GlusterFS cluster storage (Replica 3) and auto-mount to `/var/contenedores` |

### Examples:
```bash
# Only prepare system prerequisites and Docker on all nodes:
ansible-playbook -i inventory.ini site.yml --tags bootstrap,docker

# Deploy GlusterFS 3-Way Replicated Cluster Storage:
ansible-playbook -i inventory.ini glusterfs.yml

# Only deploy Gubernator services and join the cluster:
ansible-playbook -i inventory.ini site.yml --tags gubernator

# Only deploy Wave Scope topology:
ansible-playbook -i inventory.ini site.yml --tags wave_scope
```

---

## ⚙️ Customizing Variables (`group_vars/all.yml`)

You can customize cluster behavior in [`group_vars/all.yml`](file:///Users/mario/repositorios/gubernator/ansible/group_vars/all.yml):

```yaml
# Target version to install
gbnt_version: "v2.21.3"

# Installation paths
gbnt_install_path: "/usr/local/bin/gbnt"
gbnt_data_dir: "/var/lib/gubernator"

# Custom API Token for Port 4000
gbnt_api_token: "your-custom-secret-token"

# Features Toggle
enable_wave_scope: true
enable_sre_monitoring: true
enable_firewall_rules: true
```

---

## 🔍 Verification & Access

Once the playbook finishes:

1. **Gubernator Web Dashboard**: Open `http://<MANAGER_IP>:4001/` in your browser (default credentials: `admin` / `admin`).
2. **REST API & Swagger**: Check `http://<MANAGER_IP>:4002/swagger/index.html`.
3. **Network Topology**: Click on the **Network Topology** tab in the Web UI or visit `http://<MANAGER_IP>:4040/`.
4. **Monitoring (Grafana)**: Accessible on `http://<MANAGER_IP>:3000/`.
5. **Loki Logs Explorer**: Accessible directly via the **Loki Logs** navigation item in the Web Dashboard.
6. **CLI Node Verification**:
   ```bash
   ssh ubuntu@<MANAGER_IP>
   export GBNT_API_TOKEN="secret-token"
   gbnt node ls
   ```
