output "manager_ip" {
  description = "IPv4 address of the Gubernator Manager VM"
  value       = proxmox_vm_qemu.manager.default_ipv4_address
}

output "worker_ips" {
  description = "IPv4 addresses of the Gubernator Worker VMs"
  value       = proxmox_vm_qemu.workers[*].default_ipv4_address
}

output "gubernator_web_ui" {
  description = "URL to access the Gubernator Web UI"
  value       = "http://${proxmox_vm_qemu.manager.default_ipv4_address}:4001/"
}

output "wave_scope_topology_ui" {
  description = "URL to access Wave Scope Network Topology UI"
  value       = "http://${proxmox_vm_qemu.manager.default_ipv4_address}:4040/"
}

output "grafana_monitoring_ui" {
  description = "URL to access Grafana Monitoring"
  value       = "http://${proxmox_vm_qemu.manager.default_ipv4_address}:3000/"
}

output "ssh_manager_command" {
  description = "SSH command to connect to Manager VM"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${proxmox_vm_qemu.manager.default_ipv4_address}"
}
