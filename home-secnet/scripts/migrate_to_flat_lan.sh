#!/usr/bin/env bash
set -euo pipefail

echo "[10] Migrating to flat LAN (no VLANs) and hardening updates..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# shellcheck source=./lib/env.sh
source "$ROOT_DIR/scripts/lib/env.sh"

ensure_env_file
load_env

if [[ "${USE_VLANS:-false}" == "false" ]]; then
  echo "[10] USE_VLANS already false. Nothing to migrate."
else
  read -r -p "[10] Confirm migrating to flat LAN (will remove VLAN subinterfaces) [y/N]: " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then echo "[10] Aborted."; exit 1; fi
  write_env USE_VLANS false
  export USE_VLANS=false
fi

if [[ $EUID -ne 0 ]]; then
  echo "[10] Host-level changes require root on Proxmox. Re-run as root for full migration of bridges and VM NIC tags."
else
  echo "[10] Updating Proxmox bridges to non-VLAN-aware..."
  bash "$ROOT_DIR/scripts/configure_bridges.sh"

  echo "[10] Ensuring Logging VM NIC has no VLAN tag..."
  if qm status "$LOG_VM_ID" >/dev/null 2>&1; then
    cfg=$(qm config "$LOG_VM_ID" | awk -F': ' '/^net0:/ {print $2}')
    # remove ,tag=... if present, preserve MAC and other params
    newcfg=$(echo "$cfg" | sed -E 's/,tag=[0-9]+//g')
    if [[ "$cfg" != "$newcfg" ]]; then
      echo "[10] Updating net0: $cfg -> $newcfg"
      qm set "$LOG_VM_ID" --net0 "$newcfg"
    else
      echo "[10] Logging VM NIC already untagged."
    fi
  else
    echo "[10] Logging VM $LOG_VM_ID not found; skipping NIC tag update."
  fi
fi

echo "[10] Regenerating router configs for flat LAN..."
bash "$ROOT_DIR/scripts/06_generate_router_configs.sh"

echo "[10] Pushing new configs and applying on Router VM..."
bash "$ROOT_DIR/scripts/07_push_router_configs.sh"

echo "[10] Migration complete. Verify connectivity and services with: bash scripts/09_postcheck.sh"
