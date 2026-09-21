# Proxmox to Azure portability notes

The original Zabbix implementation was deployed as a Debian 13 unprivileged Proxmox LXC. This repository keeps the validated application configuration but changes the infrastructure boundary so it can run on an Azure Linux VM.

## Retained

- Zabbix 7.0 server and Agent 2 roles;
- PostgreSQL 17 role;
- TimescaleDB role with the validated 2.29.2 server/loader pin;
- Zabbix TimescaleDB conversion checks;
- runtime-only database secret handling;
- explicit deployment safety gate.

## Removed

- Proxmox provider and LXC Terraform;
- CT IDs, Proxmox node names and storage names;
- homelab IP addresses and host inventory;
- Proxmox SSH key paths;
- the `lxc_systemd_mount_baseline` role and LXC-specific systemd mount masks;
- homelab-specific comments and runtime paths.

## Changed for Azure

- Terraform now targets AzureRM and provisions a Debian 13 Gen2 VM;
- the platform playbook validates Debian 13 rather than a fixed hostname/IP;
- database secret environment variable is `ZABBIX_DB_PASSWORD`;
- remote agent server address is supplied through `ZABBIX_SERVER_ADDRESS`;
- Azure NSG rules make SSH, frontend and trapper exposure explicit and CIDR-scoped;
- Terraform outputs can be converted to Ansible inventory with `scripts/render-inventory.sh`.

This is an IaC transfer, not a state migration: existing Proxmox Terraform state must not be copied into this repository or imported into the Azure configuration.
