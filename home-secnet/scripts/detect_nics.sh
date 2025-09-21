#!/usr/bin/env bash
set -euo pipefail

echo "[00] Detecting NICs and suggesting topology..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# shellcheck source=./lib/env.sh
source "$ROOT_DIR/scripts/lib/env.sh"

ensure_env_file
load_env

# Detect physical NICs (skip virtual bridges and veth)
mapfile -t PHYS < <(ls -1 /sys/class/net | grep -vE 'lo|vmbr|tap|veth|fwln|fwpr|fwbr' | xargs -I{} bash -lc '[[ -d "/sys/class/net/{}/device" ]] && echo {}' || true)

COUNT=${#PHYS[@]}
echo "[00] Found physical interfaces: ${PHYS[*]:-none} (count=$COUNT)"

if (( COUNT == 0 )); then
  echo "[00] No physical NICs found. Are you running on Proxmox host?" >&2
  exit 1
fi

if (( COUNT == 1 )); then
  echo "[00] One NIC detected: ${PHYS[0]}"
  echo "[00] Strongly recommend adding a USB 3.0 gigabit NIC for WAN or LAN trunk."
  echo "[00] Fallback one-NIC mode: vmbr0=WAN only; cannot provide LAN trunk."
  read -r -p "Proceed with one-NIC fallback? [y/N]: " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "[00] Aborting. Add a second NIC and re-run."
    exit 1
  fi
  PHYS_WAN_IF="${PHYS[0]}"
  PHYS_LAN_IF="" # none available
else
  # Prefer to choose internal as LAN and USB as WAN (heuristic)
  WAN_CANDIDATE="${PHYS[0]}"
  LAN_CANDIDATE="${PHYS[1]}"
  # crude USB detection
  for IF in "${PHYS[@]}"; do
    if readlink -f "/sys/class/net/$IF" | grep -q usb; then
      WAN_CANDIDATE="$IF"
    fi
  done
  PHYS_WAN_IF="$WAN_CANDIDATE"
  PHYS_LAN_IF="$LAN_CANDIDATE"
  echo "[00] Guessing WAN=$PHYS_WAN_IF, LAN trunk=$PHYS_LAN_IF"
  # Allow override
  read -r -p "Use WAN interface ($PHYS_WAN_IF)? [Y/n]: " a1
  if [[ "$a1" =~ ^[Nn]$ ]]; then
    echo "Available: ${PHYS[*]}"; read -r -p "Enter WAN IF: " PHYS_WAN_IF
  fi
  read -r -p "Use LAN trunk interface ($PHYS_LAN_IF)? [Y/n]: " a2
  if [[ "$a2" =~ ^[Nn]$ ]]; then
    echo "Available: ${PHYS[*]}"; read -r -p "Enter LAN IF: " PHYS_LAN_IF
  fi
  # Ensure WAN and LAN are not the same
  while [[ -n "${PHYS_LAN_IF:-}" && "$PHYS_WAN_IF" == "$PHYS_LAN_IF" ]]; do
    echo "[00] WAN and LAN cannot be the same interface ($PHYS_WAN_IF)."
    echo "Available: ${PHYS[*]}"
    read -r -p "Enter WAN IF: " PHYS_WAN_IF
    read -r -p "Enter LAN IF (different from WAN): " PHYS_LAN_IF
  done
fi

# Update .env with detected values
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

awk -v wan="$PHYS_WAN_IF" -v lan="$PHYS_LAN_IF" '
  /^PHYS_WAN_IF=/ { sub(/=.*/, "=" wan); print; next }
  /^PHYS_LAN_IF=/ { sub(/=.*/, "=" lan); print; next }
  { print }
' "$ENV_FILE" > "$tmp_file"

mv "$tmp_file" "$ENV_FILE"
echo "[00] Wrote PHYS_WAN_IF=$PHYS_WAN_IF, PHYS_LAN_IF=${PHYS_LAN_IF:-} to .env"
echo "[00] Done."
