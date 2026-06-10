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

# --- ALTA DISPONIBILIDAD: MULTI-AZ SUBREDS ---
resource "aws_vpc" "vpc_modulo4" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "vpc-smartcampus-m4-prod" }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "subnet-public-1-m4-prod" }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "subnet-public-2-m4-prod" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "subnet-private-1-m4-prod" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "subnet-private-2-m4-prod" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_modulo4.id
  tags   = { Name = "igw-modulo4-prod" }
}

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

# --- BASTION HOST PRODUCCIÓN ---
resource "aws_instance" "bastion_host" {
  ami                         = "ami-0c7217cdde317cfec" 
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  associate_public_ip_address = true 
  vpc_security_group_ids      = [aws_security_group.sg_microservicios.id]
  key_name                    = "vockey" 
  tags                        = { Name = "Bastion-Host-UCE-M4-prod" }
}

# --- SECURITY GROUP UNIFICADO CON INGRESS DE PUERTOS ---
resource "aws_security_group" "sg_microservicios" {
  name        = "sg_apps_uce_m4_prod"
  description = "Control de accesos elasticos para Produccion"
  vpc_id      = aws_vpc.vpc_modulo4.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
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

resource "aws_instance" "mongodb_server" {
  ami                    = "ami-0c7217cdde317cfec"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.sg_microservicios.id]
  key_name               = "vockey" 
  tags                   = { Name = "MongoDB-Server-UCE-M4-prod" }
}

# --- PLANTILLA DE LANZAMIENTO (LAUNCH TEMPLATE PARA CONTENEDORES PROD) ---
resource "aws_launch_template" "template_apps" {
  name_prefix   = "template-uce-m4-prod"
  image_id      = "ami-0440d3b780d96b29d" # AMI Optimizada de Fabrica con Docker
  instance_type = "t3.medium"
  key_name      = "vockey" 

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sg_microservicios.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo systemctl start docker
              sudo systemctl enable docker
               
              sudo docker run -d -p 8001:8000 --name risk-service --restart unless-stopped xaandrade/academic-risk-service:prod-latest
              sudo docker run -d -p 8002:8000 --name notify-service --restart unless-stopped xaandrade/notification-service:prod-latest
              sudo docker run -d -p 8003:8000 --name tracking-service --restart unless-stopped xaandrade/tracking-service:prod-latest
              EOF
  )
}

# --- ELB (APPLICATION LOAD BALANCER PÚBLICO) ---
resource "aws_lb" "load_balancer" {
  name               = "elb-uce-m4-prod"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_microservicios.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# --- TARGET GROUPS Y LISTENERS REQUERIDOS ---
resource "aws_lb_target_group" "tg_tracking" {
  name        = "tg-tracking-prod-m4"
  port        = 8003
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc_modulo4.id
  target_type = "instance"
  health_check {
    path = "/"
    port = "8003"
  }
}

resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = "8003"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_tracking.arn
  }
}

# --- AUTO SCALING GROUP (ALTA DISPONIBILIDAD REAL CON NODOS RÉPLICA) ---
resource "aws_autoscaling_group" "asg_produccion" {
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  desired_capacity    = 2 # Levanta 2 réplicas distribuidas en zonas diferentes
  max_size            = 4
  min_size            = 1

  launch_template {
    id      = aws_launch_template.template_apps.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg_tracking.arn]
}