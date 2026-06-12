terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "s3-smartcampus-uce-m4-prod1"
    key    = "prod/terraform.tfstate"
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
    Name = "vpc-smartcampus-m4-prod"
  }
}

# =====================================================
# SUBNETS PUBLICAS
# =====================================================

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.vpc_modulo4.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-public-1-m4-prod"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.vpc_modulo4.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-public-2-m4-prod"
  }
}

# =====================================================
# SUBNETS PRIVADAS
# =====================================================

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "subnet-private-1-m4-prod"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "subnet-private-2-m4-prod"
  }
}

# =====================================================
# INTERNET GATEWAY
# =====================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_modulo4.id

  tags = {
    Name = "igw-modulo4-prod"
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
}

resource "aws_route_table_association" "pub_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "pub_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# =====================================================
# EIP NAT
# =====================================================

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# =====================================================
# NAT GATEWAY
# =====================================================

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [
    aws_internet_gateway.igw
  ]
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
}

resource "aws_route_table_association" "private_1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_2_assoc" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}

# =====================================================
# SECURITY GROUP
# =====================================================

resource "aws_security_group" "sg_microservicios" {
  name   = "sg_apps_uce_m4_prod"
  vpc_id = aws_vpc.vpc_modulo4.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8001
    to_port     = 8003
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
    aws_security_group.sg_microservicios.id
  ]

  key_name = "vockey"

  tags = {
    Name = "Bastion-Host-UCE-M4-prod"
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
    Name = "MongoDB-Server-UCE-M4-prod"
  }
}

# =====================================================
# LAUNCH TEMPLATE
# =====================================================

resource "aws_launch_template" "template_apps" {

  name_prefix   = "template-uce-m4-prod-"
  image_id      = "ami-0440d3b780d96b29d"
  instance_type = "t3.medium"

  key_name = "vockey"

  network_interfaces {
    associate_public_ip_address = false
    security_groups = [
      aws_security_group.sg_microservicios.id
    ]
  }

  user_data = base64encode(<<-EOF
#!/bin/bash

dnf update -y

dnf install docker -y

systemctl enable docker
systemctl start docker

docker pull xaandrade/academic-risk-service:prod-latest
docker pull xaandrade/notification-service:prod-latest
docker pull xaandrade/tracking-service:prod-latest

docker run -d \
--name academic-risk \
--restart unless-stopped \
-p 8001:8000 \
xaandrade/academic-risk-service:prod-latest

docker run -d \
--name notification-service \
--restart unless-stopped \
-p 8002:8000 \
xaandrade/notification-service:prod-latest

docker run -d \
--name tracking-service \
--restart unless-stopped \
-p 8003:8000 \
xaandrade/tracking-service:prod-latest

EOF
  )
}

# =====================================================
# TARGET GROUP
# =====================================================

resource "aws_lb_target_group" "tg_tracking" {

  name        = "tg-tracking-prod"
  port        = 8003
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc_modulo4.id
  target_type = "instance"

  health_check {
    path = "/"
    port = "8003"
  }
}

# =====================================================
# LOAD BALANCER
# =====================================================

resource "aws_lb" "load_balancer" {

  name               = "alb-smartcampus-prod"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.sg_microservicios.id
  ]

  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]
}

# =====================================================
# LISTENER
# =====================================================

resource "aws_lb_listener" "listener_http" {

  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 8003
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_tracking.arn
  }
}

# =====================================================
# AUTO SCALING GROUP
# =====================================================

resource "aws_autoscaling_group" "asg_produccion" {

  name = "asg_produccion"

  desired_capacity = 2
  max_size         = 4
  min_size         = 1

  vpc_zone_identifier = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  launch_template {
    id      = aws_launch_template.template_apps.id
    version = "$Latest"
  }

  target_group_arns = [
    aws_lb_target_group.tg_tracking.arn
  ]

  tag {
    key                 = "Name"
    value               = "asg_produccion"
    propagate_at_launch = true
  }
}