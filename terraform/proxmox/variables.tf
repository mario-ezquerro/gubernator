variable "pm_api_url" {
  description = "Proxmox API URL (e.g. https://192.168.1.100:8006/api2/json)"
  type        = string
}

variable "pm_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
}

variable "pm_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "Proxmox Node name to host VMs"
  type        = string
  default     = "pve"
}

variable "template_name" {
  description = "Name of cloud-init VM template (e.g. ubuntu-2404-template)"
  type        = string
  default     = "ubuntu-2404-template"
}

variable "cluster_name" {
  description = "Prefix name for VMs"
  type        = string
  default     = "gbnt"
}

variable "manager_cores" {
  description = "CPU cores for Manager VM"
  type        = number
  default     = 4
}

variable "manager_memory" {
  description = "RAM in MB for Manager VM"
  type        = number
  default     = 8192
}

variable "worker_cores" {
  description = "CPU cores for Worker VM"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "RAM in MB for Worker VM"
  type        = number
  default     = 4096
}

variable "worker_count" {
  description = "Number of worker VMs"
  type        = number
  default     = 2
}

variable "disk_storage" {
  description = "Proxmox storage pool for VM disks (e.g. local-lvm, zfs-pool)"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Disk size (e.g. 30G)"
  type        = string
  default     = "30G"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key (used for Ansible inventory output)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  description = "Default SSH user created via Cloud-Init"
  type        = string
  default     = "ubuntu"
}

# --- Dedicated Storage Network Variables (Dual-NIC Architecture) ---

variable "management_bridge" {
  description = "Proxmox Linux Bridge for Management & Ingress traffic (e.g. vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "storage_bridge" {
  description = "Proxmox Linux Bridge for dedicated GlusterFS Storage traffic (e.g. vmbr1)"
  type        = string
  default     = "vmbr1"
}

variable "enable_dual_nic" {
  description = "Attach secondary NIC for dedicated GlusterFS storage network"
  type        = bool
  default     = true
}

variable "storage_subnet_prefix" {
  description = "IP prefix for static storage network (e.g. 10.10.100)"
  type        = string
  default     = "10.10.100"
}

