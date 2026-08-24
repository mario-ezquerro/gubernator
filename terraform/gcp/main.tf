terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --- 1. VPC Network & Subnet ---

resource "google_compute_network" "gbnt_net" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gbnt_subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.gbnt_net.id
}

# --- 2. Firewall Rules ---

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.gbnt_net.name

  allow {
    protocol = "all"
  }

  source_ranges = ["10.0.0.0/16"]
}

resource "google_compute_firewall" "allow_public" {
  name    = "${var.cluster_name}-allow-public"
  network = google_compute_network.gbnt_net.name

  # SSH, Web UI, API, Ingress, Observability, Wave Scope
  allow {
    protocol = "tcp"
    ports = [
      "22",
      "80",
      "443",
      "53",
      "3000",
      "3100",
      "4000",
      "4001",
      "4002",
      "4040",
      "8081",
      "9090",
      "16686"
    ]
  }

  allow {
    protocol = "udp"
    ports    = ["53"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# --- 3. Compute Instances (Manager & Workers) ---

resource "google_compute_instance" "manager" {
  name         = "${var.cluster_name}-manager"
  machine_type = var.manager_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gbnt_subnet.id
    access_config {} # Public IPv4 NAT
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(pathexpand(var.ssh_public_key_path))}"
  }

  tags = ["gubernator", "manager"]
}

resource "google_compute_instance" "workers" {
  count        = var.worker_count
  name         = "${var.cluster_name}-worker-${count.index + 1}"
  machine_type = var.worker_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gbnt_subnet.id
    access_config {} # Public IPv4 NAT
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(pathexpand(var.ssh_public_key_path))}"
  }

  tags = ["gubernator", "worker"]
}

# --- 4. Automated Ansible Inventory Generation ---

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tpl", {
    manager_ip         = google_compute_instance.manager.network_interface[0].access_config[0].nat_ip
    manager_storage_ip = google_compute_instance.manager.network_interface[0].network_ip
    worker_ips         = google_compute_instance.workers[*].network_interface[0].access_config[0].nat_ip
    worker_storage_ips = google_compute_instance.workers[*].network_interface[0].network_ip
    ssh_user           = var.ssh_user
    ssh_key            = var.ssh_private_key_path
  })
  filename = "${path.module}/../../ansible/inventory.ini"
}
