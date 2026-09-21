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

public_ip="$(terraform -chdir="$TF_DIR" output -raw zabbix_public_ip 2>/dev/null || true)"
private_ip="$(terraform -chdir="$TF_DIR" output -raw zabbix_private_ip)"
admin_user="$(terraform -chdir="$TF_DIR" output -raw zabbix_admin_username)"
vm_name="$(terraform -chdir="$TF_DIR" output -raw zabbix_vm_name)"

target="$public_ip"
if [[ -z "$target" ]]; then
  target="$private_ip"
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<YAML
---
all:
  children:
    zabbix_servers:
      hosts:
        ${vm_name}:
          ansible_host: ${target}
          ansible_user: ${admin_user}
          ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY}
YAML

chmod 600 "$OUT"
printf 'Wrote %s\n' "$OUT"
printf 'Target: %s (%s)\n' "$vm_name" "$target"
