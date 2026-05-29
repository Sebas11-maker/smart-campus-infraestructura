variable "aws_region" {
  description = "Región de AWS donde se desplegará"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Entorno de despliegue (qa o prod)"
  type        = string
}