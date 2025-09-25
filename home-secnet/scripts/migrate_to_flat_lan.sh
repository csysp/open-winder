#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"; [[ -f "$LIB_PATH" ]] && source "$LIB_PATH"

echo "[13] Migrating to flat LAN (no VLANs) and hardening updates..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/env.sh
source "$ROOT_DIR/scripts/lib/env.sh"

ensure_env_file
load_env

if [[ "${USE_VLANS:-false}" == "false" ]]; then
  echo "[13] USE_VLANS already false. Nothing to migrate."
else
  read -r -p "[13] Confirm migrating to flat LAN (will remove VLAN subinterfaces) [y/N]: " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then echo "[13] Aborted."; exit 1; fi
  write_env USE_VLANS false
  export USE_VLANS=false
fi

if [[ $EUID -ne 0 ]]; then
  echo "[13] Host-level changes require root on Proxmox. Re-run as root for full migration of bridges and VM NIC tags."
else
  echo "[13] Updating Proxmox bridges to non-VLAN-aware..."
  bash "$ROOT_DIR/scripts/configure_bridges.sh"

  echo "[13] Logging VM removed from stack; skipping VM NIC updates."
fi

echo "[13] Regenerating router configs for flat LAN..."
bash "$ROOT_DIR/scripts/render_router_configs.sh"

echo "[13] Pushing new configs and applying on Router VM..."
bash "$ROOT_DIR/scripts/apply_router_configs.sh"

echo "[13] Migration complete. Verify connectivity and services with: bash scripts/verify_deploy.sh"
