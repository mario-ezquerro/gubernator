terraform {
  required_version = ">= 1.5.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

# --- 1. SSH Key ---

resource "digitalocean_ssh_key" "gbnt_key" {
  name       = "${var.cluster_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# --- 2. VPC ---

resource "digitalocean_vpc" "gbnt_vpc" {
  name     = "${var.cluster_name}-vpc"
  region   = var.region
  ip_range = "10.0.0.0/16"
}

# --- 3. Droplets (Manager & Workers) ---

resource "digitalocean_droplet" "manager" {
  name     = "${var.cluster_name}-manager"
  image    = var.image
  region   = var.region
  size     = var.manager_size
  vpc_uuid = digitalocean_vpc.gbnt_vpc.id
  ssh_keys = [digitalocean_ssh_key.gbnt_key.fingerprint]

  tags = ["gubernator", "manager"]
}

resource "digitalocean_droplet" "workers" {
  count    = var.worker_count
  name     = "${var.cluster_name}-worker-${count.index + 1}"
  image    = var.image
  region   = var.region
  size     = var.worker_size
  vpc_uuid = digitalocean_vpc.gbnt_vpc.id
  ssh_keys = [digitalocean_ssh_key.gbnt_key.fingerprint]

  tags = ["gubernator", "worker"]
}

# --- 4. Cloud Firewall ---

resource "digitalocean_firewall" "gbnt_fw" {
  name = "${var.cluster_name}-firewall"

  droplet_ids = concat([digitalocean_droplet.manager.id], digitalocean_droplet.workers[*].id)

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Gubernator Web Dashboard
  inbound_rule {
    protocol         = "tcp"
    port_range       = "4001"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Gubernator API & Observability
  inbound_rule {
    protocol         = "tcp"
    port_range       = "4000-4002"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Ingress HTTP / HTTPS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # CoreDNS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "53"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "53"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Wave Scope Topology
  inbound_rule {
    protocol         = "tcp"
    port_range       = "4040"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # SRE Observability Stack
  inbound_rule {
    protocol         = "tcp"
    port_range       = "3000"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "3100"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "9090"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "8081"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "16686"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound rules (All traffic allowed)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# --- 5. Automated Ansible Inventory Generation ---

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tpl", {
    manager_ip = digitalocean_droplet.manager.ipv4_address
    worker_ips = digitalocean_droplet.workers[*].ipv4_address
    ssh_user   = var.ssh_user
    ssh_key    = var.ssh_private_key_path
  })
  filename = "${path.module}/../../ansible/inventory.ini"
}
