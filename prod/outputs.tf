output "load_balancer_dns" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS del ALB para Postman / pruebas QA y PROD"
}

output "asg_name" {
  value       = aws_autoscaling_group.asg_produccion.name
  description = "Auto Scaling Group activo en producción"
}

output "nat_gateway_id" {
  value       = aws_nat_gateway.nat_gateway.id
  description = "NAT Gateway PROD"
}