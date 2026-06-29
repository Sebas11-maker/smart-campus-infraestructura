output "bastion_public_ip" {
  value       = aws_instance.bastion_host.public_ip
  description = "IP Pública del Bastion para acceso perimetral seguro"
}

output "qa_nodes_private_ips" {
  value = {
    node_communications = aws_instance.app_node_1_qa.private_ip
    node_analytics      = aws_instance.app_node_2_qa.private_ip
    mongodb             = aws_instance.mongodb_server.private_ip
  }
  description = "Direcciones IP Privadas de los nodos consolidados en QA"
}