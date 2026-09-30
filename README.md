# Zabbix Azure IaC

Standalone Infrastructure as Code for deploying a two-VM Zabbix 7.0 monitoring platform on Microsoft Azure.

This repository was extracted from a working Zabbix IaC implementation and made cloud-portable. The reusable Ansible application layer is retained, while the original Proxmox/LXC provisioning and homelab-specific inventory are deliberately excluded.


## Easiest install: guided script

If you are new to Azure, Terraform or Ansible, use the interactive installer instead of editing Terraform files by hand.

The script asks you for the important settings, shows sensible defaults, signs you in to Azure if needed, creates a Terraform plan, asks again before creating any chargeable resources, generates the two-host Ansible inventory and installs Zabbix. The database password is entered with hidden input and is kept only in the script process; it is not written to Git or to `terraform.tfvars`.

From the repository root:

```bash
chmod +x scripts/install-zabbix-azure.sh
./scripts/install-zabbix-azure.sh
```

You will be prompted for:

- Azure subscription;
- Azure region;
- operating system: **Debian 13** or **Ubuntu 24.04 LTS**;
- resource group, frontend VM name and database VM name;
- SSH administrator username and existing SSH key;
- the public IP/CIDR allowed to administer the VM;
- whether to expose the Zabbix web interface directly (the safer default is **No**, using an SSH tunnel);
- an optional network allowed to use Zabbix active checks on TCP/10051;
- separate Azure VM sizes for the frontend/server and database;
- a Zabbix database password of at least 24 characters.

The script checks that `az`, `terraform`, `ansible-playbook`, `ansible-galaxy` and `ssh` are installed before it starts. It will **not** run `terraform apply` until you have reviewed the Terraform plan and explicitly answered yes.

After a successful deployment it checks PostgreSQL, Zabbix Server, Zabbix Agent 2, Nginx and PHP-FPM and prints the command needed to access the frontend.

> Azure resources can incur charges. Keep the generated Terraform state and `terraform.tfvars` files safe because they are required to manage or destroy the deployment later. Both are ignored by Git.

## What it deploys

The platform is split into two Azure Linux VMs:

```text
Internet / admin network
          |
          | SSH 22 / optional web 8080 / Zabbix 10051
          v
+---------------------------+
| zabbix-frontend-01        |
| Zabbix Server 7.0         |
| Nginx + PHP frontend      |
| Zabbix Agent 2            |
+-------------+-------------+
              |
              | private VNet only
              | PostgreSQL TCP/5432
              v
+---------------------------+
| zabbix-db-01              |
| PostgreSQL 17             |
| TimescaleDB 2.29.2        |
| Zabbix Agent 2            |
+---------------------------+
```

Terraform creates:

- an Azure resource group;
- one virtual network and subnet;
- separate frontend and database network security groups;
- an optional static public IP attached only to the frontend VM;
- separate network interfaces;
- a frontend/server VM;
- a private-only database VM with no public IP.

The database NSG permits SSH and PostgreSQL only from the frontend VM's private address. The generated Ansible inventory uses the frontend VM as an SSH jump host to administer the database VM.

Ansible configures:

- PostgreSQL 17 on the database VM;
- TimescaleDB 2.29.2 on the database VM;
- Zabbix Server 7.0 on the frontend VM, using the database VM over the private VNet;
- the Zabbix TimescaleDB schema;
- Zabbix Agent 2 on both VMs;
- Nginx/PHP frontend packages on the frontend VM.

## Security model

No passwords, private keys, Terraform state, populated `.tfvars`, generated inventory, or homelab addresses are stored in Git.

SSH from external networks is opened only to the frontend VM and only from CIDRs supplied in `admin_source_cidrs`. The database VM has no public IP. Its TCP/22 and TCP/5432 rules accept traffic only from the frontend VM's private IP. The Zabbix frontend on TCP/8080 and Zabbix trapper on TCP/10051 remain closed to external networks unless explicit source CIDRs are configured.

## Prerequisites

- Azure subscription and Azure CLI authentication;
- Terraform 1.9+;
- Ansible Core;
- an SSH public/private key pair;
- `community.postgresql` Ansible collection.

Authenticate to Azure:

```bash
az login
az account set --subscription '<subscription-id>'
```

## 1. Provision Azure infrastructure

```bash
cd terraform/azure
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set at least:

- `subscription_id`;
- `admin_source_cidrs`;
- `ssh_public_key_path`;
- optionally `frontend_vm_size` and `database_vm_size` if the defaults are not suitable.

Then deploy:

```bash
terraform init
terraform plan
terraform apply
```

Choose the OS with `os_type`:

```hcl
# Default
os_type = "debian-13"

# Or
os_type = "ubuntu-24.04"
```

The corresponding Azure Marketplace images are:

```text
Debian 13:       Debian:debian-13:13-gen2:latest
Ubuntu 24.04:   Canonical:ubuntu-24_04-lts:server:latest
```

The guided installer asks this question automatically; Debian 13 remains the default and the selected OS is used for both VMs.

## 2. Generate the Ansible inventory

From the repository root:

```bash
./scripts/render-inventory.sh
```

This writes `ansible/inventory/generated.yml`, which is intentionally ignored by Git. It contains a `zabbix_servers` frontend group and a `zabbix_databases` group. The database host is reached through the frontend VM with SSH ProxyJump.

## 3. Install Ansible dependency

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

## 4. Deploy Zabbix

Supply the database password at runtime. It is never written to the repository:

```bash
export ZABBIX_DB_PASSWORD='use-a-long-random-secret-here'

cd ansible
ansible-playbook \
  -i inventory/generated.yml \
  playbooks/zabbix-platform.yml \
  -e zabbix_platform_allow_deploy=true
```

The deployment gate is intentionally disabled by default and requires explicit approval with `zabbix_platform_allow_deploy=true`. The playbook first prepares PostgreSQL/TimescaleDB, then configures the frontend and imports the standard schema, and finally performs the TimescaleDB conversion while temporarily stopping frontend services.

## Frontend access

If `frontend_source_cidrs` is empty, TCP/8080 is not exposed by the Azure NSG. You can still use SSH port forwarding:

```bash
ssh -L 8080:127.0.0.1:8080 <admin-user>@<vm-public-ip>
```

Then browse to `http://127.0.0.1:8080`.

Alternatively, add trusted source CIDRs to `frontend_source_cidrs` and re-apply Terraform.

## Adding remote Zabbix Agent 2 hosts

For active agents, permit the agent network(s) to reach TCP/10051 by adding them to `zabbix_trapper_source_cidrs` in Terraform.

Set the server address at runtime before applying the agent playbook:

```bash
export ZABBIX_SERVER_ADDRESS='<zabbix-private-or-public-address>'

cd ansible
ansible-playbook \
  -i inventory/your-agents.yml \
  playbooks/zabbix-agent.yml
```

Prefer private connectivity (Azure VPN, ExpressRoute, peering, or another private path) rather than exposing Agent2/trapper traffic broadly to the internet.

## VM sizing

The defaults are intentionally modest for a small deployment:

| Role | Default size | OS disk |
| --- | --- | ---: |
| Zabbix server + frontend | `Standard_B2s` | 64 GiB |
| PostgreSQL + TimescaleDB | `Standard_B2s` | 128 GiB |

For larger environments, size the database VM independently because history/trend ingestion and TimescaleDB usually drive storage and memory requirements before the web tier does.

## Repository layout

```text
terraform/azure/       Azure infrastructure
ansible/playbooks/     Zabbix platform and agent orchestration
ansible/roles/         Reusable PostgreSQL/TimescaleDB/Zabbix roles
ansible/inventory/     Safe example and generated inventory location
scripts/               Inventory generation and GitHub bootstrap helpers
.github/workflows/     Terraform/Ansible validation
```

See `MIGRATION.md` for the portability changes made from the original Proxmox implementation.
