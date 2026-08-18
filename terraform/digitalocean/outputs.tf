output "manager_public_ip" {
  description = "Public IP of the Gubernator Manager Droplet"
  value       = digitalocean_droplet.manager.ipv4_address
}

output "worker_public_ips" {
  description = "Public IPs of the Gubernator Worker Droplets"
  value       = digitalocean_droplet.workers[*].ipv4_address
}

output "gubernator_web_ui" {
  description = "URL to access the Gubernator Web UI"
  value       = "http://${digitalocean_droplet.manager.ipv4_address}:4001/"
}

output "wave_scope_topology_ui" {
  description = "URL to access Wave Scope Network Topology UI"
  value       = "http://${digitalocean_droplet.manager.ipv4_address}:4040/"
}

output "grafana_monitoring_ui" {
  description = "URL to access Grafana Monitoring"
  value       = "http://${digitalocean_droplet.manager.ipv4_address}:3000/"
}

output "ssh_manager_command" {
  description = "SSH command to connect to Manager Droplet"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${digitalocean_droplet.manager.ipv4_address}"
}
