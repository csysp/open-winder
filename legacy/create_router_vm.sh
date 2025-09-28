#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Create the Router VM on Proxmox.
# Inputs: .env via scripts/lib/env.sh; VERBOSE (optional)
# Outputs: none
# Side effects: Creates VM and attaches disks/network.

usage() {
  cat <<'USAGE'
Usage: create_router_vm.sh
  Creates Router VM using Proxmox qm and .env settings.

Environment:
  VERBOSE=1   Enable verbose logging
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi
# shellcheck source=scripts/lib/log.sh
# shellcheck source=home-secnet/scripts/lib/log.sh
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"
if [[ -f "$LIB_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$LIB_PATH"
fi

log_info "[06] Building Router VM..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

if [[ $EUID -ne 0 ]]; then
  echo "[06] Run as root on the Proxmox host." >&2
  exit 1
fi

TEMPLATE_VM_ID=9000

if qm status "$ROUTER_VM_ID" >/dev/null 2>&1; then
  echo "[06] Router VM $ROUTER_VM_ID already exists. Skipping creation."
else
  echo "[06] Cloning from template $TEMPLATE_VM_ID to $ROUTER_VM_ID ($ROUTER_VM_NAME)..."
  qm clone $TEMPLATE_VM_ID $ROUTER_VM_ID --name "$ROUTER_VM_NAME" --full 1 --storage "$DISK_STORAGE"
  qm set $ROUTER_VM_ID --memory "$ROUTER_RAM" --cores "$ROUTER_CPU"
  qm set $ROUTER_VM_ID --scsihw virtio-scsi-pci
  qm set $ROUTER_VM_ID --net0 virtio,bridge=${VM_BR_WAN}
  # LAN trunk: omit VLAN tag to allow VLAN subinterfaces inside guest
  qm set $ROUTER_VM_ID --net1 virtio,bridge=${VM_BR_LAN}
  qm set $ROUTER_VM_ID --agent enabled=1
  tmpkey=$(mktemp)
  echo "$ROUTER_ADMIN_PUBKEY" > "$tmpkey"
  qm set $ROUTER_VM_ID --ciuser "$ROUTER_ADMIN_USER" --sshkey "$tmpkey"
  rm -f "$tmpkey"
  qm set $ROUTER_VM_ID --cipassword ''
  qm set $ROUTER_VM_ID --ide2 ${ISO_STORAGE}:cloudinit
  qm set $ROUTER_VM_ID --boot c --bootdisk scsi0
  qm set $ROUTER_VM_ID --serial0 socket --vga serial0
  qm set $ROUTER_VM_ID --onboot 1
fi

echo "[06] Router VM ready. Start it if needed: qm start $ROUTER_VM_ID"
