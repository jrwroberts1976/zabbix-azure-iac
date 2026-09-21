#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform/azure"
ANSIBLE_DIR="$ROOT/ansible"
TFVARS="$TF_DIR/terraform.tfvars"
INVENTORY="$ANSIBLE_DIR/inventory/generated.yml"

say() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

prompt() {
  local var_name="$1" label="$2" default_value="${3:-}" value
  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " value
    value="${value:-$default_value}"
  else
    read -r -p "$label: " value
  fi
  printf -v "$var_name" '%s' "$value"
}

prompt_yes_no() {
  local var_name="$1" label="$2" default_value="${3:-N}" value
  while true; do
    read -r -p "$label [${default_value}/$([[ "$default_value" == "Y" ]] && echo N || echo Y)]: " value
    value="${value:-$default_value}"
    case "${value,,}" in
      y|yes) printf -v "$var_name" '%s' "yes"; return 0 ;;
      n|no)  printf -v "$var_name" '%s' "no"; return 0 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

require_command() {
  local cmd="$1" help="$2"
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required. $help"
}

valid_cidr_or_ip() {
  local value="$1"
  [[ "$value" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ ]]
}

detect_public_ip() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    printf '%s/32' "$ip"
  fi
}

say "Zabbix on Azure - guided installer"
echo "This script will create Azure resources with Terraform and configure the VM with Ansible."
echo "Azure resources can incur charges. You will see a Terraform plan before anything is created."

require_command az "Install Azure CLI: https://learn.microsoft.com/cli/azure/install-azure-cli"
require_command terraform "Install Terraform: https://developer.hashicorp.com/terraform/install"
require_command ansible-playbook "Install Ansible Core: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html"
require_command ansible-galaxy "Install Ansible Core: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html"
require_command ssh "Install an OpenSSH client."

say "Azure sign-in"
if ! az account show >/dev/null 2>&1; then
  echo "You are not signed in to Azure. Opening Azure login..."
  az login
fi

mapfile -t subscriptions < <(az account list --query "[].{name:name,id:id,isDefault:isDefault}" -o tsv)
[[ ${#subscriptions[@]} -gt 0 ]] || die "No Azure subscriptions are available to this account."

default_subscription_id="$(az account show --query id -o tsv)"
default_subscription_name="$(az account show --query name -o tsv)"
echo "Current Azure subscription: $default_subscription_name ($default_subscription_id)"
prompt SUBSCRIPTION_ID "Azure subscription ID" "$default_subscription_id"
az account set --subscription "$SUBSCRIPTION_ID"

say "Azure VM settings"
prompt LOCATION "Azure region" "UK South"
prompt RESOURCE_GROUP "Resource group name" "rg-zabbix-prod-uks"
prompt VM_NAME "VM name" "zabbix-azure-01"
prompt ADMIN_USERNAME "SSH admin username" "zabbixadmin"
prompt VM_SIZE "Azure VM size" "Standard_B2s"

prompt SSH_PUBLIC_KEY "SSH public key path" "$HOME/.ssh/id_ed25519.pub"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY/#\~/$HOME}"
[[ -f "$SSH_PUBLIC_KEY" ]] || die "SSH public key not found: $SSH_PUBLIC_KEY"

if [[ "$SSH_PUBLIC_KEY" == *.pub ]]; then
  SSH_PRIVATE_KEY="${SSH_PUBLIC_KEY%.pub}"
else
  prompt SSH_PRIVATE_KEY "SSH private key path used by Ansible" "$HOME/.ssh/id_ed25519"
  SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY/#\~/$HOME}"
fi
[[ -f "$SSH_PRIVATE_KEY" ]] || die "SSH private key not found: $SSH_PRIVATE_KEY"

say "Network access"
detected_cidr="$(detect_public_ip)"
if [[ -n "$detected_cidr" ]]; then
  echo "Detected your current public IP as: $detected_cidr"
fi
while true; do
  prompt ADMIN_CIDR "IP/CIDR allowed to SSH to the VM" "${detected_cidr:-198.51.100.10/32}"
  valid_cidr_or_ip "$ADMIN_CIDR" && break
  echo "Please enter an IPv4 address or CIDR, for example 203.0.113.25/32."
done

prompt_yes_no EXPOSE_FRONTEND "Expose Zabbix TCP/8080 directly to this same CIDR? (No = safer SSH tunnel)" "N"
if [[ "$EXPOSE_FRONTEND" == "yes" ]]; then
  FRONTEND_CIDRS="[\"$ADMIN_CIDR\"]"
else
  FRONTEND_CIDRS="[]"
fi

prompt TRAPPER_CIDR "CIDR allowed to reach Zabbix active-check port 10051 (leave blank for none)" ""
if [[ -n "$TRAPPER_CIDR" ]]; then
  valid_cidr_or_ip "$TRAPPER_CIDR" || die "Invalid trapper CIDR: $TRAPPER_CIDR"
  TRAPPER_CIDRS="[\"$TRAPPER_CIDR\"]"
else
  TRAPPER_CIDRS="[]"
fi

say "Zabbix database password"
echo "Enter a strong password of at least 24 characters. It will NOT be written to disk."
while true; do
  read -r -s -p "Database password: " ZABBIX_DB_PASSWORD
  echo
  [[ ${#ZABBIX_DB_PASSWORD} -ge 24 ]] || { echo "Password must be at least 24 characters."; continue; }
  read -r -s -p "Confirm database password: " ZABBIX_DB_PASSWORD_CONFIRM
  echo
  [[ "$ZABBIX_DB_PASSWORD" == "$ZABBIX_DB_PASSWORD_CONFIRM" ]] && break
  echo "Passwords did not match. Try again."
done
unset ZABBIX_DB_PASSWORD_CONFIRM
export ZABBIX_DB_PASSWORD

say "Writing Terraform variables"
cat > "$TFVARS" <<EOF_TFVARS
subscription_id = "$SUBSCRIPTION_ID"
location        = "$LOCATION"

resource_group_name = "$RESOURCE_GROUP"
vm_name             = "$VM_NAME"
admin_username       = "$ADMIN_USERNAME"
ssh_public_key_path  = "$SSH_PUBLIC_KEY"

admin_source_cidrs = ["$ADMIN_CIDR"]
frontend_source_cidrs = $FRONTEND_CIDRS
zabbix_trapper_source_cidrs = $TRAPPER_CIDRS

enable_public_ip = true
vnet_address_space      = ["10.42.0.0/16"]
subnet_address_prefixes = ["10.42.1.0/24"]

vm_size                      = "$VM_SIZE"
os_disk_size_gb              = 64
os_disk_storage_account_type = "StandardSSD_LRS"

tags = {
  application = "zabbix"
  managed_by  = "terraform"
  environment = "production"
}
EOF_TFVARS
chmod 600 "$TFVARS"
echo "Created $TFVARS (ignored by Git)."

say "Terraform initialization"
terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" fmt terraform.tfvars
terraform -chdir="$TF_DIR" validate

say "Terraform plan"
terraform -chdir="$TF_DIR" plan -out=tfplan

warn "The next step creates Azure resources that may cost money."
prompt_yes_no APPLY_TERRAFORM "Apply this Terraform plan?" "N"
if [[ "$APPLY_TERRAFORM" != "yes" ]]; then
  echo "Stopped before creating resources. Re-run this script when you are ready."
  exit 0
fi

terraform -chdir="$TF_DIR" apply tfplan
rm -f "$TF_DIR/tfplan"

say "Generating Ansible inventory"
SSH_PRIVATE_KEY="$SSH_PRIVATE_KEY" "$ROOT/scripts/render-inventory.sh"

say "Installing Ansible collection"
ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml"

PUBLIC_IP="$(terraform -chdir="$TF_DIR" output -raw zabbix_public_ip)"
TARGET_IP="$PUBLIC_IP"
if [[ -z "$TARGET_IP" ]]; then
  TARGET_IP="$(terraform -chdir="$TF_DIR" output -raw zabbix_private_ip)"
fi

say "Waiting for SSH on $TARGET_IP"
for attempt in $(seq 1 30); do
  if ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -i "$SSH_PRIVATE_KEY" \
    "$ADMIN_USERNAME@$TARGET_IP" true >/dev/null 2>&1; then
    echo "SSH is ready."
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    die "SSH did not become ready. Check the Azure NSG, your current public IP, and the VM boot diagnostics."
  fi
  printf 'Waiting for SSH... attempt %s/30\n' "$attempt"
  sleep 10
done

say "Configuring Zabbix with Ansible"
(
  cd "$ANSIBLE_DIR"
  ansible-playbook \
    -i "$INVENTORY" \
    playbooks/zabbix-platform.yml \
    -e zabbix_platform_allow_deploy=true
)

say "Verification"
ssh \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  -i "$SSH_PRIVATE_KEY" \
  "$ADMIN_USERNAME@$TARGET_IP" \
  "sudo systemctl is-active postgresql zabbix-server zabbix-agent2 nginx php8.4-fpm && curl -fsSI http://127.0.0.1:8080/ | head -1"

cat <<EOF_DONE

============================================================
Zabbix deployment completed.
============================================================
VM:         $VM_NAME
Public IP:  ${PUBLIC_IP:-not enabled}
SSH user:   $ADMIN_USERNAME

EOF_DONE

if [[ "$EXPOSE_FRONTEND" == "yes" ]]; then
  echo "Open the Zabbix frontend from your trusted network:"
  echo "  http://$TARGET_IP:8080"
else
  echo "The frontend was kept private. Start this SSH tunnel:"
  echo
  echo "  ssh -i '$SSH_PRIVATE_KEY' -L 8080:127.0.0.1:8080 '$ADMIN_USERNAME@$TARGET_IP'"
  echo
  echo "Then browse to: http://127.0.0.1:8080"
fi

echo
echo "Terraform state and terraform.tfvars remain local and are ignored by Git."
echo "Keep them safe; they are needed to manage or destroy this Azure deployment later."
