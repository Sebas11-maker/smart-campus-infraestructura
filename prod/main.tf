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
  region = "us-east-1"
}

# =====================================================
# VPC PRODUCCIÓN
# =====================================================
resource "aws_vpc" "vpc_prod" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-prod-m4"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# =====================================================
# SUBNETS PUBLICAS (ALTA DISPONIBILIDAD)
# =====================================================
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.vpc_prod.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-1-prod"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.vpc_prod.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-2-prod"
  }
}

# =====================================================
# INTERNET GATEWAY
# =====================================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_prod.id

  tags = {
    Name = "igw-prod"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# =====================================================
# NAT GATEWAY
# =====================================================
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "nat-prod"
  }
}

# =====================================================
# SECURITY GROUP MICROSERVICIOS
# =====================================================
resource "aws_security_group" "sg_microservicios" {
  name        = "microservices-prod-sg"
  description = "Allow HTTP and SSH traffic"
  vpc_id      = aws_vpc.vpc_prod.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
# LAUNCH TEMPLATE
# =====================================================
resource "aws_launch_template" "template_apps" {
  name_prefix   = "lt-prod-m4-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.sg_microservicios.id]

  lifecycle {
    create_before_destroy = true
  }
}

# =====================================================
# TARGET GROUP
# =====================================================
resource "aws_lb_target_group" "tg_tracking" {
  name     = "tg-tracking-prod"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id

  health_check {
    path = "/"
  }
}

# =====================================================
# LOAD BALANCER
# =====================================================
resource "aws_lb" "load_balancer" {
  name               = "elb-uce-m4-prod"
  load_balancer_type = "application"

  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  security_groups = [aws_security_group.sg_microservicios.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_tracking.arn
  }
}

# =====================================================
# AUTO SCALING GROUP (HA PROD)
# =====================================================
resource "aws_autoscaling_group" "asg_produccion" {
  name                = "asg-prod-m4"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2

  vpc_zone_identifier = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  target_group_arns = [aws_lb_target_group.tg_tracking.arn]

  launch_template {
    id      = aws_launch_template.template_apps.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}

# =====================================================
# ROUTES
# =====================================================
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc_prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}