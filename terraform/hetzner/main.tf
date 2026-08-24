terraform {
  required_version = ">= 1.5.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# --- 1. SSH Key ---

resource "hcloud_ssh_key" "gbnt_key" {
  name       = "${var.cluster_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# --- 2. Private Network & Subnet ---

resource "hcloud_network" "gbnt_net" {
  name     = "${var.cluster_name}-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "gbnt_subnet" {
  network_id   = hcloud_network.gbnt_net.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# --- 3. Firewall ---

resource "hcloud_firewall" "gbnt_fw" {
  name = "${var.cluster_name}-firewall"

  # SSH
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "SSH"
  }

  # Gubernator Web Dashboard
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "4001"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Gubernator Web UI"
  }

  # Gubernator REST API & Observability
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "4000-4002"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Gubernator API & Observability"
  }

  # Caddy Ingress (HTTP & HTTPS)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "HTTP Ingress"
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "HTTPS Ingress"
  }

  # CoreDNS
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "53"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "CoreDNS TCP"
  }

  rule {
    direction = "in"
    protocol  = "udp"
    port      = "53"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "CoreDNS UDP"
  }

  # Wave Scope Topology
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "4040"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Wave Scope Topology"
  }

  # SRE Monitoring (Grafana, Loki, Prometheus, Jaeger, cAdvisor)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "3000"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Grafana"
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "3100"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Loki"
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "9090"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Prometheus"
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "8081"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "cAdvisor"
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "16686"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Jaeger UI"
  }
}

# --- 4. Server Instances (Manager & Workers) ---

resource "hcloud_server" "manager" {
  name        = "${var.cluster_name}-manager"
  image       = var.image
  server_type = var.manager_server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.gbnt_key.id]
  firewall_ids = [hcloud_firewall.gbnt_fw.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.gbnt_net.id
    ip         = "10.0.1.10"
  }

  labels = {
    role    = "manager"
    project = "gubernator"
  }

  depends_on = [hcloud_network_subnet.gbnt_subnet]
}

resource "hcloud_server" "workers" {
  count       = var.worker_count
  name        = "${var.cluster_name}-worker-${count.index + 1}"
  image       = var.image
  server_type = var.worker_server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.gbnt_key.id]
  firewall_ids = [hcloud_firewall.gbnt_fw.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.gbnt_net.id
    ip         = "10.0.1.1${count.index + 1}"
  }

  labels = {
    role    = "worker"
    project = "gubernator"
  }

  depends_on = [hcloud_network_subnet.gbnt_subnet]
}

# --- 5. Automated Ansible Inventory Generation ---

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tpl", {
    manager_ip         = hcloud_server.manager.ipv4_address
    manager_storage_ip = "10.0.1.10"
    worker_ips         = hcloud_server.workers[*].ipv4_address
    worker_storage_ips = [for i in range(var.worker_count) : "10.0.1.1${i + 1}"]
    ssh_user           = var.ssh_user
    ssh_key            = var.ssh_private_key_path
  })
  filename = "${path.module}/../../ansible/inventory.ini"
}
