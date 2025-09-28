#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Detect Proxmox and idempotently setup vmbr0 (WAN) and vmbr1 (LAN) bridges.
# Inputs: VERBOSE (optional); PHYS_WAN_IF/PHYS_LAN_IF (optional overrides)
# Outputs: Configures /etc/network/interfaces.d/bridges if on Proxmox
# Side effects: Modifies network config; prompts unless YES=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"

detect_proxmox() { command -v pveversion >/dev/null 2>&1 && command -v pve-firewall >/dev/null 2>&1; }

if ! detect_proxmox; then
  echo "[hv] Proxmox not detected; skipping bridge setup."; exit 0
fi

WAN_IF="${PHYS_WAN_IF:-}"
LAN_IF="${PHYS_LAN_IF:-}"
if [[ -z "$WAN_IF" || -z "$LAN_IF" ]]; then
  echo "[hv] PHYS_WAN_IF/PHYS_LAN_IF not set; attempting detection via ip link..."
  mapfile -t ifs < <(ip -o link show | awk -F': ' '{print $2}' | grep -Ev 'lo|vmbr|tap|fwln|fwpr|veth' | head -n 2)
  WAN_IF="${WAN_IF:-${ifs[0]:-}}"
  LAN_IF="${LAN_IF:-${ifs[1]:-}}"
fi

if [[ -z "$WAN_IF" || -z "$LAN_IF" ]]; then
  echo "[hv] Could not detect two physical NICs. Set PHYS_WAN_IF and PHYS_LAN_IF in .env." >&2
  exit 1
fi

echo "[hv] Will configure vmbr0 (WAN:$WAN_IF) and vmbr1 (LAN:$LAN_IF)."
if [[ "${YES:-0}" != "1" ]]; then
  read -r -p "Proceed with bridge configuration? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "[hv] Aborted"; exit 1; }
fi

mkdir -p /etc/network/interfaces.d
TMP="/tmp/winder-bridges-$$"
umask 022
cat >"$TMP" <<EOF
auto vmbr0
iface vmbr0 inet manual
    bridge-ports $WAN_IF
    bridge-stp off
    bridge-fd 0

auto vmbr1
iface vmbr1 inet manual
    bridge-ports $LAN_IF
    bridge-stp off
    bridge-fd 0
EOF

mv -f "$TMP" /etc/network/interfaces.d/bridges
echo "[hv] Bridges configured. Apply with: ifreload -a (will disrupt network)."

