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
# SUBNETS PUBLICAS
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
# SECURITY GROUP (ABRE PUERTOS PARA LOS 3 MICROS)
# =====================================================
resource "aws_security_group" "sg_microservicios" {
  name        = "microservices-prod-v2-sg"
  description = "Allow HTTP traffic for all services"
  vpc_id      = aws_vpc.vpc_prod.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8002
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
# LAUNCH TEMPLATE (DESPLIEGA LOS 3 CONTENEDORES)
# =====================================================
resource "aws_launch_template" "template_apps" {
  name_prefix   = "lt-prod-m4-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.sg_microservicios.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user

    # 1. Bajar las 3 imágenes desde DockerHub
    docker pull docker.io/xaandrade/tracking-service:prod
    docker pull docker.io/xaandrade/notification-service:prod
    docker pull docker.io/xaandrade/academic-risk-service:prod

    # 2. Levantar Microservicio 1: TRACKING (Puerto Interno 8000 -> Externo 8000)
    docker run -d -p 8000:8000 --name tracking-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/tracking-service:prod

    # 3. Levantar Microservicio 2: NOTIFICATION (Puerto Interno 8000 -> Externo 8001)
    docker run -d -p 8001:8000 --name notification-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/notification-service:prod

    # 4. Levantar Microservicio 3: ACADEMIC RISK (Puerto Interno 8000 -> Externo 8002)
    docker run -d -p 8002:8000 --name academic-risk-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/academic-risk-service:prod
  EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =====================================================
# TARGET GROUPS INDEPENDIENTES
# =====================================================
resource "aws_lb_target_group" "tg_tracking" {
  name     = "tg-tracking-prod-v2" 
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_notification" {
  name     = "tg-notification-prod" 
  port     = 8001
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_academic_risk" {
  name     = "tg-academic-risk-prod" 
  port     = 8002
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

# =====================================================
# LOAD BALANCER Y LISTENER BASE
# =====================================================
resource "aws_lb" "load_balancer" {
  name               = "elb-uce-m4-prod"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.sg_microservicios.id]

  lifecycle { prevent_destroy = true }
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
# REGLAS INTELIGENTES DE ENRUTAMIENTO (PATH-BASED ROUTING)
# =====================================================
resource "aws_lb_listener_rule" "rule_notification" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_notification.arn
  }

  condition {
    path_pattern {
      values = ["/notifications", "/notifications*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_academic_risk" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_academic_risk.arn
  }

  condition {
    path_pattern {
      values = ["/risk", "/risk*"]
    }
  }
}

# =====================================================
# AUTO SCALING GROUP (HA CLUSTER)
# =====================================================
resource "aws_autoscaling_group" "asg_produccion" {
  name                = "asg-prod-m4"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  
  # El ASG ahora vigila y alimenta los 3 destinos en simultáneo
  target_group_arns   = [
    aws_lb_target_group.tg_tracking.arn,
    aws_lb_target_group.tg_notification.arn,
    aws_lb_target_group.tg_academic_risk.arn
  ]

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