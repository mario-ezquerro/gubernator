variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region (e.g. europe-west1, us-central1)"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "europe-west1-b"
}

variable "cluster_name" {
  description = "Name prefix for cluster resources"
  type        = string
  default     = "gbnt"
}

variable "manager_machine_type" {
  description = "GCP machine type for Manager (e.g. e2-medium or e2-standard-2)"
  type        = string
  default     = "e2-medium"
}

variable "worker_machine_type" {
  description = "GCP machine type for Workers (e.g. e2-small or e2-medium)"
  type        = string
  default     = "e2-small"
}

variable "worker_count" {
  description = "Number of worker nodes to provision"
  type        = number
  default     = 2
}

variable "image" {
  description = "Boot disk image"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
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
  description = "Default SSH user"
  type        = string
  default     = "ubuntu"
}

variable "disk_size_gb" {
  description = "Disk size in GB"
  type        = number
  default     = 30
}
