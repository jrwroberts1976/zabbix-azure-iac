#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-$ROOT/terraform/azure}"
OUT="${OUT:-$ROOT/ansible/inventory/generated.yml}"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-$HOME/.ssh/id_ed25519}"

command -v terraform >/dev/null 2>&1 || {
  echo "terraform is required" >&2
  exit 1
}

frontend_public_ip="$(terraform -chdir="$TF_DIR" output -raw zabbix_frontend_public_ip 2>/dev/null || true)"
frontend_private_ip="$(terraform -chdir="$TF_DIR" output -raw zabbix_frontend_private_ip)"
database_private_ip="$(terraform -chdir="$TF_DIR" output -raw zabbix_database_private_ip)"
admin_user="$(terraform -chdir="$TF_DIR" output -raw zabbix_admin_username)"
frontend_vm_name="$(terraform -chdir="$TF_DIR" output -raw zabbix_frontend_vm_name)"
database_vm_name="$(terraform -chdir="$TF_DIR" output -raw zabbix_database_vm_name)"

frontend_target="$frontend_public_ip"
if [[ -z "$frontend_target" ]]; then
  frontend_target="$frontend_private_ip"
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<YAML
---
all:
  children:
    zabbix_servers:
      hosts:
        ${frontend_vm_name}:
          ansible_host: ${frontend_target}
          ansible_user: ${admin_user}
          ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY}
          zabbix_private_ip: ${frontend_private_ip}

    zabbix_databases:
      hosts:
        ${database_vm_name}:
          ansible_host: ${database_private_ip}
          ansible_user: ${admin_user}
          ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY}
          ansible_ssh_common_args: "-o ProxyJump=${admin_user}@${frontend_target}"
          zabbix_private_ip: ${database_private_ip}
YAML

chmod 600 "$OUT"
printf 'Wrote %s\n' "$OUT"
printf 'Frontend: %s (%s)\n' "$frontend_vm_name" "$frontend_target"
printf 'Database: %s (%s via frontend jump host)\n' "$database_vm_name" "$database_private_ip"
