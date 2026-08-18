variable "do_token" {
  description = "DigitalOcean Personal Access Token"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name prefix for cluster resources"
  type        = string
  default     = "gbnt"
}

variable "region" {
  description = "DigitalOcean region slug (fra1, ams3, nyc3, sfo3, lon1)"
  type        = string
  default     = "fra1"
}

variable "manager_size" {
  description = "Droplet size slug for Manager"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "worker_size" {
  description = "Droplet size slug for Workers"
  type        = string
  default     = "s-2vcpu-2gb"
}

variable "worker_count" {
  description = "Number of worker Droplets to provision"
  type        = number
  default     = 2
}

variable "image" {
  description = "Droplet OS image slug (ubuntu-24-04-x64, debian-12-x64, rocky-9-x64)"
  type        = string
  default     = "ubuntu-24-04-x64"
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
  description = "Default SSH user (root on DigitalOcean by default)"
  type        = string
  default     = "root"
}
