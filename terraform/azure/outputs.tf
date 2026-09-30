output "zabbix_frontend_vm_name" {
  description = "Azure VM name for the Zabbix server/frontend."
  value       = azurerm_linux_virtual_machine.frontend.name
}

output "zabbix_database_vm_name" {
  description = "Azure VM name for PostgreSQL/TimescaleDB."
  value       = azurerm_linux_virtual_machine.database.name
}

output "zabbix_admin_username" {
  description = "SSH administrator username used by both VMs."
  value       = var.admin_username
}

output "zabbix_frontend_private_ip" {
  description = "Private IP address of the Zabbix server/frontend VM."
  value       = azurerm_network_interface.frontend.private_ip_address
}

output "zabbix_database_private_ip" {
  description = "Private IP address of the PostgreSQL/TimescaleDB VM."
  value       = azurerm_network_interface.database.private_ip_address
}

output "zabbix_frontend_public_ip" {
  description = "Public IP address of the frontend VM, or empty when public IP is disabled."
  value       = var.enable_public_ip ? azurerm_public_ip.frontend[0].ip_address : ""
}

output "zabbix_frontend_port" {
  description = "Nginx frontend port configured by Ansible."
  value       = 8080
}

output "zabbix_database_port" {
  description = "PostgreSQL port reachable only from the frontend VM."
  value       = 5432
}
