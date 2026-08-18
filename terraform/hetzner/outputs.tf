output "manager_public_ip" {
  description = "Public IPv4 of Gubernator Manager"
  value       = hcloud_server.manager.ipv4_address
}

output "worker_public_ips" {
  description = "Public IPv4 addresses of Gubernator Workers"
  value       = hcloud_server.workers[*].ipv4_address
}

output "gubernator_web_ui" {
  description = "URL to access the Gubernator Web UI"
  value       = "http://${hcloud_server.manager.ipv4_address}:4001/"
}

output "wave_scope_topology_ui" {
  description = "URL to access Wave Scope Network Topology UI"
  value       = "http://${hcloud_server.manager.ipv4_address}:4040/"
}

output "grafana_monitoring_ui" {
  description = "URL to access Grafana Monitoring"
  value       = "http://${hcloud_server.manager.ipv4_address}:3000/"
}

output "ssh_manager_command" {
  description = "SSH connect command to Manager"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${hcloud_server.manager.ipv4_address}"
}
