terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 3.0.1-rc6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
}

# --- 1. Manager VM ---

resource "proxmox_vm_qemu" "manager" {
  name        = "${var.cluster_name}-manager"
  target_node = var.target_node
  clone       = var.template_name
  os_type     = "cloud-init"
  cores       = var.manager_cores
  sockets     = 1
  cpu_type    = "host"
  memory      = var.manager_memory
  scsihw      = "virtio-scsi-pci"
  agent       = 1
  onboot      = true

  disks {
    scsi {
      scsi0 {
        disk {
          storage = var.disk_storage
          size    = var.disk_size
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  ciuser  = var.ssh_user
  sshkeys = file(pathexpand(var.ssh_public_key_path))
  ipconfig0 = "ip=dhcp"
}

# --- 2. Worker VMs ---

resource "proxmox_vm_qemu" "workers" {
  count       = var.worker_count
  name        = "${var.cluster_name}-worker-${count.index + 1}"
  target_node = var.target_node
  clone       = var.template_name
  os_type     = "cloud-init"
  cores       = var.worker_cores
  sockets     = 1
  cpu_type    = "host"
  memory      = var.worker_memory
  scsihw      = "virtio-scsi-pci"
  agent       = 1
  onboot      = true

  disks {
    scsi {
      scsi0 {
        disk {
          storage = var.disk_storage
          size    = var.disk_size
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  ciuser  = var.ssh_user
  sshkeys = file(pathexpand(var.ssh_public_key_path))
  ipconfig0 = "ip=dhcp"
}

# --- 3. Automated Ansible Inventory Generation ---

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tpl", {
    manager_ip = proxmox_vm_qemu.manager.default_ipv4_address
    worker_ips = proxmox_vm_qemu.workers[*].default_ipv4_address
    ssh_user   = var.ssh_user
    ssh_key    = var.ssh_private_key_path
  })
  filename = "${path.module}/../../ansible/inventory.ini"
}
