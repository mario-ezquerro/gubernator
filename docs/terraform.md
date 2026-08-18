# Multi-Cloud Infrastructure with Terraform

Gubernator provides a complete suite of Infrastructure as Code (IaC) templates in the [`terraform/`](https://github.com/mario-ezquerro/gubernator/tree/main/terraform) directory. These templates provision virtual machines, networks, firewalls, and security groups across major cloud providers and automatically generate the inventory for [Ansible Automation](ansible.md).

---

## 🏗️ Architecture & Supported Clouds

```mermaid
graph TD
    subgraph Cloud Providers
        AWS[AWS EC2 & VPC]
        HETZNER[Hetzner Cloud & Firewall]
        DO[DigitalOcean Droplets & VPC]
        GCP[Google Cloud Compute & VPC]
        PVE[Proxmox VE On-Premise]
    end

    Cloud Providers -->|terraform apply| TF[Terraform State & Resources]
    TF -->|Generates| INV[ansible/inventory.ini]
    INV -->|ansible-playbook site.yml| GBNT[Fully Operational Gubernator Cluster]
```

### Supported Providers:
* **Amazon Web Services (AWS)** (`terraform/aws/`): VPC, Subnets, Internet Gateway, Security Groups, and EC2 instances.
* **Hetzner Cloud** (`terraform/hetzner/`): Private networks, Cloud Firewalls, and ARM64 (`cax11`/`cax21`) or x86 instances.
* **DigitalOcean** (`terraform/digitalocean/`): Custom VPC, Cloud Firewalls, and Droplets.
* **Google Cloud Platform (GCP)** (`terraform/gcp/`): Custom VPC, Firewall rules, and Compute Engine instances with public NAT.
* **Proxmox VE** (`terraform/proxmox/`): On-premise homelab VM cloning via Cloud-Init.

---

## 🚀 End-to-End Deployment Workflow

### 1. Provision Cloud Infrastructure with Terraform
Select your provider and configure credentials:

```bash
cd terraform/hetzner
cp terraform.tfvars.example terraform.tfvars
# Fill in your API token and SSH keys
terraform init
terraform apply
```

### 2. Configure Gubernator with Ansible
Terraform automatically generates `ansible/inventory.ini`. Now run the Ansible playbook:

```bash
cd ../../ansible
ansible-playbook -i inventory.ini site.yml
```

### 3. Access Your Cluster
Once completed:
* **Gubernator Web Dashboard**: `http://<MANAGER_IP>:4001/`
* **Wave Scope Network Topology**: `http://<MANAGER_IP>:4040/`
* **Grafana Monitoring**: `http://<MANAGER_IP>:3000/`
* **Loki Logs Explorer**: Tab in Web UI or `http://<MANAGER_IP>:3100/`
* **REST API & Swagger**: `http://<MANAGER_IP>:4002/swagger/index.html`
