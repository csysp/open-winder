#!/usr/bin/env bash
set -euo pipefail

echo "[07] Building Logging VM..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

if [[ $EUID -ne 0 ]]; then
  echo "[07] Run as root on the Proxmox host." >&2
  exit 1
fi

TEMPLATE_VM_ID=9000

if qm status "$LOG_VM_ID" >/dev/null 2>&1; then
  echo "[07] Logging VM $LOG_VM_ID already exists. Skipping creation."
else
  echo "[07] Cloning from template $TEMPLATE_VM_ID to $LOG_VM_ID ($LOG_VM_NAME)..."
  qm clone $TEMPLATE_VM_ID $LOG_VM_ID --name "$LOG_VM_NAME" --full 1 --storage "$DISK_STORAGE"
  qm set $LOG_VM_ID --memory "$LOG_RAM" --cores "$LOG_CPU"
  qm set $LOG_VM_ID --scsihw virtio-scsi-pci
  if [[ "${USE_VLANS:-false}" == "true" ]]; then
    qm set $LOG_VM_ID --net0 virtio,bridge=${VM_BR_LAN},tag=${VLAN_TRUSTED}
  else
    qm set $LOG_VM_ID --net0 virtio,bridge=${VM_BR_LAN}
  fi
  qm set $LOG_VM_ID --agent enabled=1
  tmpkey=$(mktemp)
  echo "$LOG_ADMIN_PUBKEY" > "$tmpkey"
  qm set $LOG_VM_ID --ciuser "$LOG_ADMIN_USER" --sshkey "$tmpkey"
  rm -f "$tmpkey"
  qm set $LOG_VM_ID --cipassword ''
  qm set $LOG_VM_ID --ide2 ${ISO_STORAGE}:cloudinit
  qm set $LOG_VM_ID --boot c --bootdisk scsi0
  qm set $LOG_VM_ID --serial0 socket --vga serial0
  qm set $LOG_VM_ID --onboot 1
fi

echo "[07] Logging VM ready. Start it if needed: qm start $LOG_VM_ID"
