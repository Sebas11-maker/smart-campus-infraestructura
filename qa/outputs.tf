output "bastion_public_ip" {
  value       = aws_instance.bastion_host.public_ip
  description = "IP Pública del Bastion para conexión SSH y Túneles"
}

output "qa_microservices_private_ips" {
  value = {
    academic_risk = aws_instance.sec_service_qa.private_ip
    notification  = aws_instance.notify_service_qa.private_ip
    tracking      = aws_instance.tracking_service_qa.private_ip
    mongodb       = aws_instance.mongodb_server.private_ip
  }
  description = "Direcciones IP Privadas para mapeo interno desde GitHub Actions"
}