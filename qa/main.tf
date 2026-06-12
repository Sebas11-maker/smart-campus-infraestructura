terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "s3-smartcampus-uce-m4-qa1"
    key    = "qa/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# =====================================================
# VPC
# =====================================================

resource "aws_vpc" "vpc_modulo4" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-smartcampus-m4-qa"
  }
}

# =====================================================
# SUBNETS
# =====================================================

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.vpc_modulo4.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-public-1-m4-qa"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "subnet-private-1-m4-qa"
  }
}

# =====================================================
# INTERNET GATEWAY
# =====================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_modulo4.id

  tags = {
    Name = "igw-modulo4-qa"
  }
}

# =====================================================
# PUBLIC ROUTE TABLE
# =====================================================

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc_modulo4.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table-qa"
  }
}

resource "aws_route_table_association" "pub_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

# =====================================================
# NAT GATEWAY
# =====================================================

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat-eip-qa"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [
    aws_internet_gateway.igw
  ]

  tags = {
    Name = "nat-gateway-qa"
  }
}

# =====================================================
# PRIVATE ROUTE TABLE
# =====================================================

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc_modulo4.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "private-route-table-qa"
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

# =====================================================
# SECURITY GROUP BASTION
# =====================================================

resource "aws_security_group" "sg_bastion" {
  name   = "sg_bastion_m4_qa"
  vpc_id = aws_vpc.vpc_modulo4.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =====================================================
# SECURITY GROUP MICROSERVICIOS
# =====================================================

resource "aws_security_group" "sg_microservicios" {
  name        = "sg_apps_uce_m4_qa"
  description = "Control de acceso perimetral para entorno QA"
  vpc_id      = aws_vpc.vpc_modulo4.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8010
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =====================================================
# BASTION HOST
# =====================================================

resource "aws_instance" "bastion_host" {
  ami                         = "ami-0c7217cdde317cfec"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.sg_bastion.id
  ]

  key_name = "vockey"

  tags = {
    Name = "Bastion-Host-UCE-M4-qa"
  }
}

# =====================================================
# MONGODB
# =====================================================

resource "aws_instance" "mongodb_server" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_1.id

  vpc_security_group_ids = [
    aws_security_group.sg_microservicios.id
  ]

  key_name = "vockey"

  tags = {
    Name = "MongoDB-Server-UCE-M4-qa"
  }
}

# =====================================================
# USER DATA DOCKER
# =====================================================

locals {
  docker_install_script = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install docker -y
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
  EOF
}

# =====================================================
# ACADEMIC RISK SERVICE
# =====================================================

resource "aws_instance" "sec_service_qa" {
  ami           = "ami-0440d3b780d96b29d"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_1.id

  vpc_security_group_ids = [
    aws_security_group.sg_microservicios.id
  ]

  key_name = "vockey"

  user_data = local.docker_install_script

  tags = {
    Name = "Academic-Risk-Service-QA-M4"
  }
}

# =====================================================
# NOTIFICATION SERVICE
# =====================================================

resource "aws_instance" "notify_service_qa" {
  ami           = "ami-0440d3b780d96b29d"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_1.id

  vpc_security_group_ids = [
    aws_security_group.sg_microservicios.id
  ]

  key_name = "vockey"

  user_data = local.docker_install_script

  tags = {
    Name = "Notification-Service-QA-M4"
  }
}

# =====================================================
# TRACKING SERVICE
# =====================================================

resource "aws_instance" "tracking_service_qa" {
  ami           = "ami-0440d3b780d96b29d"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_1.id

  vpc_security_group_ids = [
    aws_security_group.sg_microservicios.id
  ]

  key_name = "vockey"

  user_data = local.docker_install_script

  tags = {
    Name = "Tracking-Service-QA-M4"
  }
}
