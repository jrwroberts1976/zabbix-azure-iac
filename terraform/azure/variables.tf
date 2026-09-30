variable "subscription_id" {
  description = "Azure subscription ID used by the AzureRM provider."
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "UK South"
}

variable "resource_group_name" {
  description = "Resource group created for the Zabbix platform."
  type        = string
  default     = "rg-zabbix-prod-uks"
}

variable "frontend_vm_name" {
  description = "Azure VM/computer name for the Zabbix server and web frontend."
  type        = string
  default     = "zabbix-frontend-01"
}

variable "database_vm_name" {
  description = "Azure VM/computer name for PostgreSQL and TimescaleDB."
  type        = string
  default     = "zabbix-db-01"
}

variable "admin_username" {
  description = "Administrative SSH username."
  type        = string
  default     = "zabbixadmin"
}

variable "ssh_public_key_path" {
  description = "Path to an existing SSH public key."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_source_cidrs" {
  description = "CIDRs allowed to SSH to the frontend VM. Keep this tightly scoped."
  type        = list(string)

  validation {
    condition     = length(var.admin_source_cidrs) > 0
    error_message = "At least one trusted SSH source CIDR must be supplied."
  }
}

variable "frontend_source_cidrs" {
  description = "CIDRs allowed to reach the Zabbix frontend on TCP/8080. Empty means no public frontend rule."
  type        = list(string)
  default     = []
}

variable "zabbix_trapper_source_cidrs" {
  description = "CIDRs allowed to reach Zabbix Server trapper/active-check port TCP/10051. Empty means no inbound rule."
  type        = list(string)
  default     = []
}

variable "enable_public_ip" {
  description = "Create and attach a static public IP to the frontend VM. The database VM remains private-only."
  type        = bool
  default     = true
}

variable "vnet_address_space" {
  description = "Address space for the Zabbix VNet."
  type        = list(string)
  default     = ["10.42.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the Zabbix subnet."
  type        = list(string)
  default     = ["10.42.1.0/24"]
}

variable "os_type" {
  description = "Operating system image used by both Zabbix VMs."
  type        = string
  default     = "debian-13"

  validation {
    condition     = contains(["debian-13", "ubuntu-24.04"], var.os_type)
    error_message = "os_type must be either debian-13 or ubuntu-24.04."
  }
}

variable "frontend_vm_size" {
  description = "Azure VM size for the Zabbix server/frontend VM."
  type        = string
  default     = "Standard_B2s"
}

variable "database_vm_size" {
  description = "Azure VM size for the PostgreSQL/TimescaleDB VM."
  type        = string
  default     = "Standard_B2s"
}

variable "frontend_os_disk_size_gb" {
  description = "Frontend VM OS disk size in GiB."
  type        = number
  default     = 64
}

variable "database_os_disk_size_gb" {
  description = "Database VM OS disk size in GiB."
  type        = number
  default     = 128
}

variable "os_disk_storage_account_type" {
  description = "Managed OS disk storage type."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default = {
    application = "zabbix"
    managed_by  = "terraform"
    environment = "production"
  }
}
