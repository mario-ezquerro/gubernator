output "manager_public_ip" {
  description = "Public IP of the Gubernator Manager node"
  value       = aws_instance.manager.public_ip
}

output "worker_public_ips" {
  description = "Public IPs of the Gubernator Worker nodes"
  value       = aws_instance.workers[*].public_ip
}

output "gubernator_web_ui" {
  description = "URL to access the Gubernator Web UI"
  value       = "http://${aws_instance.manager.public_ip}:4001/"
}

output "wave_scope_topology_ui" {
  description = "URL to access the Wave Scope Network Topology UI"
  value       = "http://${aws_instance.manager.public_ip}:4040/"
}

output "grafana_monitoring_ui" {
  description = "URL to access Grafana Monitoring"
  value       = "http://${aws_instance.manager.public_ip}:3000/"
}

output "ssh_manager_command" {
  description = "Command to connect to the Manager node via SSH"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${aws_instance.manager.public_ip}"
}
