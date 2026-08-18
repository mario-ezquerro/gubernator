variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name prefix for cluster resources"
  type        = string
  default     = "gbnt"
}

variable "location" {
  description = "Hetzner datacenter location (fsn1, nbg1, hel1, ash, hil)"
  type        = string
  default     = "fsn1"
}

variable "manager_server_type" {
  description = "Server type for Gubernator Manager (e.g. cax11 for ARM64, cx22 for x86)"
  type        = string
  default     = "cax21" # 4 vCPU ARM, 8GB RAM, 80GB NVMe ~ €6.49/mo
}

variable "worker_server_type" {
  description = "Server type for Gubernator Workers"
  type        = string
  default     = "cax11" # 2 vCPU ARM, 4GB RAM, 40GB NVMe ~ €3.79/mo
}

variable "worker_count" {
  description = "Number of worker nodes to provision"
  type        = number
  default     = 2
}

variable "image" {
  description = "OS Image (ubuntu-24.04, debian-12, rocky-9, alma-9)"
  type        = string
  default     = "ubuntu-24.04"
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
  description = "Default SSH user (root on Hetzner by default)"
  type        = string
  default     = "root"
}
