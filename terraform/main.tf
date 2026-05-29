terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

# 
resource "aws_security_group" "sg_modulo4" {
  name        = "sg_modulo4_${var.environment}"
  description = "Permitir trafico basico para el modulo 4"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FastAPI App"
    from_port   = 8000
    to_port     = 8000
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

# 
resource "aws_instance" "app_server" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu Server 22.04 LTS en us-east-1
  instance_type = var.environment == "prod" ? "t2.medium" : "t2.micro" # ASG/Escalabilidad simulada por tamaño

  tags = {
    Name = "SmartCampus-Modulo4-${var.environment}"
  }
}