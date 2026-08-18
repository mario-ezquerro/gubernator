output "manager_public_ip" {
  description = "Public IP of the Gubernator Manager instance"
  value       = google_compute_instance.manager.network_interface[0].access_config[0].nat_ip
}

output "worker_public_ips" {
  description = "Public IPs of the Gubernator Worker instances"
  value       = google_compute_instance.workers[*].network_interface[0].access_config[0].nat_ip
}

output "gubernator_web_ui" {
  description = "URL to access the Gubernator Web UI"
  value       = "http://${google_compute_instance.manager.network_interface[0].access_config[0].nat_ip}:4001/"
}

output "wave_scope_topology_ui" {
  description = "URL to access Wave Scope Network Topology UI"
  value       = "http://${google_compute_instance.manager.network_interface[0].access_config[0].nat_ip}:4040/"
}

output "grafana_monitoring_ui" {
  description = "URL to access Grafana Monitoring"
  value       = "http://${google_compute_instance.manager.network_interface[0].access_config[0].nat_ip}:3000/"
}

output "ssh_manager_command" {
  description = "SSH command to connect to Manager instance"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${google_compute_instance.manager.network_interface[0].access_config[0].nat_ip}"
}
