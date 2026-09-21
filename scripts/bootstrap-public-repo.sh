#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="${1:-zabbix-azure-iac}"
OWNER="${GITHUB_OWNER:-jrwroberts1976}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v git >/dev/null 2>&1 || {
  echo "git is required" >&2
  exit 1
}
command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI (gh) is required" >&2
  exit 1
}

gh auth status
cd "$ROOT"

if [[ ! -d .git ]]; then
  git init -b main
fi

git add .
if ! git diff --cached --quiet; then
  git commit -m "Initial Azure-portable Zabbix IaC"
fi

gh repo create "$OWNER/$REPO_NAME" \
  --public \
  --source=. \
  --remote=origin \
  --push
