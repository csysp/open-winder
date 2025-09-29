#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Configure Proxmox bridges for Winder.
# Inputs: .env via scripts/lib/env.sh; VERBOSE (optional)
# Outputs: none
# Side effects: Configures network bridges on host.

usage() {
  cat <<'USAGE'
Usage: configure_bridges.sh
  Creates/updates Proxmox bridges according to .env.

Environment:
  VERBOSE=1   Enable verbose logging
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# Load env via helper and export for envsubst compatibility
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"
set -a; load_env; set +a

log_info "[04] Configuring Proxmox bridges (WAN vmbr0, LAN trunk vmbr1)..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "[04] Run as root on the Proxmox host." >&2
  exit 1
fi

if [[ -z "${PHYS_WAN_IF:-}" ]]; then
  echo "[04] PHYS_WAN_IF is not set. Run detect_nics.sh first." >&2
  exit 1
fi

if [[ -z "${PHYS_LAN_IF:-}" ]]; then
  echo "[04] ERROR: Only one NIC detected; system requires 2 NICs." >&2
  exit 1
fi

INTERFACES=/etc/network/interfaces
cp -a "$INTERFACES" "${INTERFACES}.bak-$(date +%s)"

add_or_replace_block() {
  local marker="$1"; shift
  local content="$*"
  if grep -q "# BEGIN ${marker}" "$INTERFACES"; then
    sed -i "/# BEGIN ${marker}/,/# END ${marker}/c\\${content}" "$INTERFACES"
  else
    printf "\n%s\n" "$content" >> "$INTERFACES"
  fi
}

WAN_BLOCK="# BEGIN HOME-SECNET-VMRB0\nauto ${VM_BR_WAN}\niface ${VM_BR_WAN} inet manual\n    bridge-ports ${PHYS_WAN_IF}\n    bridge-stp off\n    bridge-fd 0\n# END HOME-SECNET-VMRB0"
add_or_replace_block HOME-SECNET-VMRB0 "$WAN_BLOCK"

if [[ -n "${PHYS_LAN_IF:-}" ]]; then
  if [[ "${USE_VLANS:-false}" == "true" ]]; then
    LAN_BLOCK="# BEGIN HOME-SECNET-VMRB1\nauto ${VM_BR_LAN}\niface ${VM_BR_LAN} inet manual\n    bridge-ports ${PHYS_LAN_IF}\n    bridge-stp off\n    bridge-fd 0\n    bridge-vlan-aware yes\n# END HOME-SECNET-VMRB1"
  else
    LAN_BLOCK="# BEGIN HOME-SECNET-VMRB1\nauto ${VM_BR_LAN}\niface ${VM_BR_LAN} inet manual\n    bridge-ports ${PHYS_LAN_IF}\n    bridge-stp off\n    bridge-fd 0\n# END HOME-SECNET-VMRB1"
  fi
  add_or_replace_block HOME-SECNET-VMRB1 "$LAN_BLOCK"
fi

echo "[04] Bridge config written. Restarting networking..."
if systemctl is-active --quiet networking; then
  systemctl restart networking || log_warn "[04] networking restart failed; verify bridge config"
fi
echo "[04] Done."
