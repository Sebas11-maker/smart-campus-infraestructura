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

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_prod.id

  tags = {
    Name = "igw-prod"
  }

  lifecycle {
    prevent_destroy = true
  }
}

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
    to_port     = 8009
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


resource "aws_launch_template" "template_apps" {
  name_prefix   = "lt-prod-m4-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.sg_microservicios.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user

    # Levantamiento del Broker de Mensajería local en el Nodo de Producción
    docker run -d -p 5672:5672 -p 15672:15672 --name rabbitmq-prod --restart unless-stopped rabbitmq:3-management-alpine
    
    # Delay de seguridad para inicialización de sockets
    sleep 15

    # Pull masivo de imágenes oficiales
    docker pull docker.io/xaandrade/tracking-service:prod
    docker pull docker.io/xaandrade/notification-service:prod
    docker pull docker.io/xaandrade/academic-risk-service:prod
    docker pull docker.io/xaandrade/security-gateway-service:prod
    docker pull docker.io/xaandrade/chat-service:prod
    docker pull docker.io/xaandrade/dashboard-service:prod
    docker pull docker.io/xaandrade/report-service:prod
    docker pull docker.io/xaandrade/export-service:prod
    docker pull docker.io/xaandrade/analytics-service:prod
    docker pull docker.io/xaandrade/audit-service:prod

    # Inicialización de contenedores e inyección de contexto de persistencia y eventos
    docker run -d -p 8000:8000 --name tracking-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/tracking-service:prod
    
    docker run -d -p 8001:8000 --name notification-service-prod \
      -e ENV="production" \
      -e RABBITMQ_HOST="localhost" \
      -e MONGO_URI="mongodb://localhost:27017/" \
      --restart unless-stopped docker.io/xaandrade/notification-service:prod

    docker run -d -p 8002:8000 --name academic-risk-service-prod \
      -e ENV="production" \
      -e RABBITMQ_HOST="localhost" \
      --restart unless-stopped docker.io/xaandrade/academic-risk-service:prod

    docker run -d -p 8003:8000 --name security-gateway-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/security-gateway-service:prod
    docker run -d -p 8004:8000 --name chat-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/chat-service:prod
    docker run -d -p 8005:8000 --name dashboard-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/dashboard-service:prod
    docker run -d -p 8006:8000 --name report-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/report-service:prod
    docker run -d -p 8007:8000 --name export-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/export-service:prod
    docker run -d -p 8008:8000 --name analytics-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/analytics-service:prod
    docker run -d -p 8009:8000 --name audit-service-prod -e ENV="production" --restart unless-stopped docker.io/xaandrade/audit-service:prod
  EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}


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

resource "aws_lb_target_group" "tg_security" {
  name     = "tg-security-prod" 
  port     = 8003
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_chat" {
  name     = "tg-chat-prod" 
  port     = 8004
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_dashboard" {
  name     = "tg-dashboard-prod" 
  port     = 8005
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_report" {
  name     = "tg-report-prod" 
  port     = 8006
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_export" {
  name     = "tg-export-prod" 
  port     = 8007
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_analytics" {
  name     = "tg-analytics-prod" 
  port     = 8008
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "tg_audit" {
  name     = "tg-audit-prod" 
  port     = 8009
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_prod.id
  health_check { path = "/" }
}


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

resource "aws_lb_listener_rule" "rule_security" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_security.arn
  }

  condition {
    path_pattern {
      values = ["/security", "/security*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_chat" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_chat.arn
  }

  condition {
    path_pattern {
      values = ["/chat", "/chat*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_dashboard" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_dashboard.arn
  }

  condition {
    path_pattern {
      values = ["/dashboard", "/dashboard*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_report" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 60

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_report.arn
  }

  condition {
    path_pattern {
      values = ["/report", "/report*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_export" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 70

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_export.arn
  }

  condition {
    path_pattern {
      values = ["/export", "/export*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_analytics" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 80

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_analytics.arn
  }

  condition {
    path_pattern {
      values = ["/analytics", "/analytics*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_audit" {
  listener_arn = aws_lb_listener.listener_http.arn
  priority     = 90

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_audit.arn
  }

  condition {
    path_pattern {
      values = ["/audit", "/audit*"]
    }
  }
}


resource "aws_autoscaling_group" "asg_produccion" {
  name                = "asg-prod-m4"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  
  target_group_arns   = [
    aws_lb_target_group.tg_tracking.arn,
    aws_lb_target_group.tg_notification.arn,
    aws_lb_target_group.tg_academic_risk.arn,
    aws_lb_target_group.tg_security.arn,
    aws_lb_target_group.tg_chat.arn,
    aws_lb_target_group.tg_dashboard.arn,
    aws_lb_target_group.tg_report.arn,
    aws_lb_target_group.tg_export.arn,
    aws_lb_target_group.tg_analytics.arn,
    aws_lb_target_group.tg_audit.arn
  ]

  launch_template {
    id      = aws_launch_template.template_apps.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}


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