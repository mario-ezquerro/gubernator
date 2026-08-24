terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- 1. Networking (VPC, Subnet, IGW, Route Table) ---

resource "aws_vpc" "gbnt_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.cluster_name}-vpc"
    Project = "Gubernator"
  }
}

resource "aws_internet_gateway" "gbnt_igw" {
  vpc_id = aws_vpc.gbnt_vpc.id

  tags = {
    Name    = "${var.cluster_name}-igw"
    Project = "Gubernator"
  }
}

resource "aws_subnet" "gbnt_public_subnet" {
  vpc_id                  = aws_vpc.gbnt_vpc.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name    = "${var.cluster_name}-public-subnet"
    Project = "Gubernator"
  }
}

resource "aws_route_table" "gbnt_public_rt" {
  vpc_id = aws_vpc.gbnt_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gbnt_igw.id
  }

  tags = {
    Name    = "${var.cluster_name}-public-rt"
    Project = "Gubernator"
  }
}

resource "aws_route_table_association" "gbnt_public_rta" {
  subnet_id      = aws_subnet.gbnt_public_subnet.id
  route_table_id = aws_route_table.gbnt_public_rt.id
}

# --- 2. Security Group ---

resource "aws_security_group" "gbnt_sg" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for Gubernator cluster nodes"
  vpc_id      = aws_vpc.gbnt_vpc.id

  # Allow all internal cluster traffic
  ingress {
    description = "Internal cluster communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # SSH
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Gubernator Web Dashboard
  ingress {
    description = "Gubernator Web UI"
    from_port   = 4001
    to_port     = 4001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Gubernator REST API & Observability
  ingress {
    description = "Gubernator REST API & Observability"
    from_port   = 4000
    to_port     = 4002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP / HTTPS (Caddy Ingress)
  ingress {
    description = "HTTP Ingress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS Ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # CoreDNS
  ingress {
    description = "CoreDNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "CoreDNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Wave Scope Topology
  ingress {
    description = "Wave Scope Topology UI"
    from_port   = 4040
    to_port     = 4040
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SRE Monitoring (Grafana, Loki, Prometheus, Jaeger, cAdvisor)
  ingress {
    description = "Grafana Monitoring"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Loki Logs"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus Metrics"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "cAdvisor Container Metrics"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jaeger Tracing UI"
    from_port   = 16686
    to_port     = 16686
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress (Allow all outbound)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.cluster_name}-sg"
    Project = "Gubernator"
  }
}

# --- 3. Key Pair & AMI ---

resource "aws_key_pair" "gbnt_key" {
  key_name   = "${var.cluster_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Project = "Gubernator"
  }
}

# Latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- 4. EC2 Instances (Manager & Workers) ---

resource "aws_instance" "manager" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.manager_instance_type
  subnet_id              = aws_subnet.gbnt_public_subnet.id
  vpc_security_group_ids = [aws_security_group.gbnt_sg.id]
  key_name               = aws_key_pair.gbnt_key.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.cluster_name}-manager"
    Role    = "manager"
    Project = "Gubernator"
  }
}

resource "aws_instance" "workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.gbnt_public_subnet.id
  vpc_security_group_ids = [aws_security_group.gbnt_sg.id]
  key_name               = aws_key_pair.gbnt_key.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.cluster_name}-worker-${count.index + 1}"
    Role    = "worker"
    Project = "Gubernator"
  }
}

# --- 5. Automated Ansible Inventory Generation ---

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tpl", {
    manager_ip         = aws_instance.manager.public_ip
    manager_storage_ip = aws_instance.manager.private_ip
    worker_ips         = aws_instance.workers[*].public_ip
    worker_storage_ips = aws_instance.workers[*].private_ip
    ssh_user           = var.ssh_user
    ssh_key            = var.ssh_private_key_path
  })
  filename = "${path.module}/../../ansible/inventory.ini"
}
