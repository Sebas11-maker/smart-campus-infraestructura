output "bastion_public_ip" {
  value       = aws_instance.bastion_host.public_ip
  description = "IP Pública del Bastion para conexión SSH y Túneles"
}

output "qa_microservices_private_ips" {
  value = {
    academic_risk     = aws_instance.sec_service_qa.private_ip
    notification      = aws_instance.notify_service_qa.private_ip
    tracking          = aws_instance.tracking_service_qa.private_ip
    security_gateway  = aws_instance.security_gateway_qa.private_ip
    chat              = aws_instance.chat_service_qa.private_ip
    dashboard         = aws_instance.dashboard_service_qa.private_ip
    report            = aws_instance.report_service_qa.private_ip
    export            = aws_instance.export_service_qa.private_ip
    analytics         = aws_instance.analytics_service_qa.private_ip
    audit             = aws_instance.audit_service_qa.private_ip
    mongodb           = aws_instance.mongodb_server.private_ip
  }
  description = "Direcciones IP Privadas mapeadas para el entorno de QA (Módulo 4)"
}