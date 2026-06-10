output "bastion_public_ip" {
  value       = aws_instance.bastion_host.public_ip
  description = "IP del Jump Box para auditoria externa"
}

output "load_balancer_dns" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS del Balanceador de Carga para invitar en Postman Workspace"
}