terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

#S3

  backend "s3" {
    bucket         = "s3-smartcampus-uce-m4-gitops" # <--- El bucket con acceso liberado que acabas de crear
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}


resource "aws_vpc" "vpc_modulo4" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "vpc-smartcampus-m4-${var.environment}" }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "subnet-public-1-m4" }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "subnet-public-2-m4" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "subnet-private-1-m4" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.vpc_modulo4.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "subnet-private-2-m4" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_modulo4.id
  tags   = { Name = "igw-modulo4" }
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



resource "aws_instance" "bastion_host" {
  ami           = "ami-0c7217cdde317cfec" 
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "Bastion-Host-UCE-M4-${var.environment}" }
}

resource "aws_security_group" "sg_microservicios" {
  name        = "sg_apps_uce_m4_${var.environment}"
  description = "Control de acceso para el modulo 4"
  vpc_id      = aws_vpc.vpc_modulo4.id

  ingress {
    from_port   = 80
    to_port     = 80
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



resource "aws_db_subnet_group" "rds_subnets" {
  name       = "rds-subnets-uce-m4-${var.environment}"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_db_instance" "relational_db" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "15"
  instance_class       = "db.t3.micro"
  db_name              = "academic_reports_m4"
  username             = "admin_uce"
  password             = "PasswordSeguro123"
  db_subnet_group_name = aws_db_subnet_group.rds_subnets.name
  skip_final_snapshot  = true
  tags                 = { Name = "Postgres-DB-UCE-M4-${var.environment}" }
}

resource "aws_instance" "mongodb_server" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_1.id
  tags          = { Name = "MongoDB-Server-UCE-M4-${var.environment}" }
}

resource "aws_elasticache_subnet_group" "redis_subnets" {
  name       = "redis-subnets-uce-m4-${var.environment}"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_elasticache_cluster" "cache_redis" {
  cluster_id           = "redis-uce-m4-${var.environment}"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnets.name
  port                 = 6379
}



resource "aws_launch_template" "template_apps" {
  name_prefix   = "template-uce-m4-"
  image_id      = "ami-0c7217cdde317cfec"
  instance_type = var.environment == "prod" ? "t3.medium" : "t2.micro"

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sg_microservicios.id]
  }
}

resource "aws_lb" "load_balancer" {
  name               = "elb-uce-m4-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_microservicios.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_autoscaling_group" "asg_produccion" {
  count               = var.environment == "prod" ? 1 : 0
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1

  launch_template {
    id      = aws_launch_template.template_apps.id
    version = "$Latest"
  }
}

resource "aws_instance" "servidor_qa" {
  count                  = var.environment == "qa" ? 1 : 0
  ami                    = "ami-0c7217cdde317cfec"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.sg_microservicios.id]
  tags                   = { Name = "Servidor-Unico-QA-M4" }
}