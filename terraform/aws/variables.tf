variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name prefix for Gubernator cluster resources"
  type        = string
  default     = "gbnt-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "manager_instance_type" {
  description = "EC2 instance type for Gubernator Manager"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for Gubernator Workers"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of worker nodes to provision"
  type        = number
  default     = 2
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
  description = "Default SSH user for the AMI (e.g. ubuntu, ec2-user, rocky)"
  type        = string
  default     = "ubuntu"
}

variable "root_volume_size" {
  description = "Root disk volume size in GB"
  type        = number
  default     = 30
}
