output "zabbix_vm_name" {
  description = "Azure VM name."
  value       = azurerm_linux_virtual_machine.zabbix.name
}

output "zabbix_admin_username" {
  description = "SSH administrator username."
  value       = var.admin_username
}

output "zabbix_private_ip" {
  description = "Private IP address of the Zabbix VM."
  value       = azurerm_network_interface.zabbix.private_ip_address
}

output "zabbix_public_ip" {
  description = "Public IP address of the Zabbix VM, or empty when public IP is disabled."
  value       = var.enable_public_ip ? azurerm_public_ip.zabbix[0].ip_address : ""
}

output "zabbix_frontend_port" {
  description = "Nginx frontend port configured by Ansible."
  value       = 8080
}
