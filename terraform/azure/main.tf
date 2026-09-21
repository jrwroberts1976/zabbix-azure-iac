locals {
  os_images = {
    "debian-13" = {
      publisher = "Debian"
      offer     = "debian-13"
      sku       = "13-gen2"
      version   = "latest"
    }
    "ubuntu-24.04" = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
      version   = "latest"
    }
  }

  selected_os_image = local.os_images[var.os_type]

  ssh_rules = {
    for idx, cidr in var.admin_source_cidrs : tostring(idx) => {
      cidr     = cidr
      priority = 100 + idx
    }
  }

  frontend_rules = {
    for idx, cidr in var.frontend_source_cidrs : tostring(idx) => {
      cidr     = cidr
      priority = 200 + idx
    }
  }

  trapper_rules = {
    for idx, cidr in var.zabbix_trapper_source_cidrs : tostring(idx) => {
      cidr     = cidr
      priority = 300 + idx
    }
  }
}

resource "azurerm_resource_group" "zabbix" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "zabbix" {
  name                = "vnet-${var.vm_name}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.zabbix.location
  resource_group_name = azurerm_resource_group.zabbix.name
  tags                = var.tags
}

resource "azurerm_subnet" "zabbix" {
  name                 = "snet-${var.vm_name}"
  resource_group_name  = azurerm_resource_group.zabbix.name
  virtual_network_name = azurerm_virtual_network.zabbix.name
  address_prefixes     = var.subnet_address_prefixes
}

resource "azurerm_network_security_group" "zabbix" {
  name                = "nsg-${var.vm_name}"
  location            = azurerm_resource_group.zabbix.location
  resource_group_name = azurerm_resource_group.zabbix.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "ssh" {
  for_each = local.ssh_rules

  name                        = "allow-ssh-${each.key}"
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.value.cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.zabbix.name
  network_security_group_name = azurerm_network_security_group.zabbix.name
}

resource "azurerm_network_security_rule" "frontend" {
  for_each = local.frontend_rules

  name                        = "allow-zabbix-frontend-${each.key}"
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = each.value.cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.zabbix.name
  network_security_group_name = azurerm_network_security_group.zabbix.name
}

resource "azurerm_network_security_rule" "trapper" {
  for_each = local.trapper_rules

  name                        = "allow-zabbix-trapper-${each.key}"
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "10051"
  source_address_prefix       = each.value.cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.zabbix.name
  network_security_group_name = azurerm_network_security_group.zabbix.name
}

resource "azurerm_public_ip" "zabbix" {
  count = var.enable_public_ip ? 1 : 0

  name                = "pip-${var.vm_name}"
  location            = azurerm_resource_group.zabbix.location
  resource_group_name = azurerm_resource_group.zabbix.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "zabbix" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.zabbix.location
  resource_group_name = azurerm_resource_group.zabbix.name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.zabbix.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.zabbix[0].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "zabbix" {
  network_interface_id      = azurerm_network_interface.zabbix.id
  network_security_group_id = azurerm_network_security_group.zabbix.id
}

resource "azurerm_linux_virtual_machine" "zabbix" {
  name                            = var.vm_name
  computer_name                   = var.vm_name
  resource_group_name             = azurerm_resource_group.zabbix.name
  location                        = azurerm_resource_group.zabbix.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.zabbix.id]
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = local.selected_os_image.publisher
    offer     = local.selected_os_image.offer
    sku       = local.selected_os_image.sku
    version   = local.selected_os_image.version
  }

  boot_diagnostics {}
}
