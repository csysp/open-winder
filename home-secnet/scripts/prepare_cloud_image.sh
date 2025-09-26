#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# shellcheck source=home-secnet/scripts/lib/log.sh
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"; [[ -f "$LIB_PATH" ]] && source "$LIB_PATH"

log_info "[05] Fetching Ubuntu 24.04 cloud image and creating template..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

if [[ $EUID -ne 0 ]]; then
  echo "[05] Run as root on the Proxmox host." >&2
  exit 1
fi

echo "[05] Using storages: ISO=$ISO_STORAGE, DISK=$DISK_STORAGE"

TEMPLATE_VM_ID=9000
if qm status $TEMPLATE_VM_ID >/dev/null 2>&1; then
  echo "[05] Template VM $TEMPLATE_VM_ID already exists. Skipping."
  exit 0
fi

IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMG_DIR="/var/lib/vz/template/iso"
IMG_FILE="$IMG_DIR/noble-server-cloudimg-amd64.img"
mkdir -p "$IMG_DIR"
if ! command -v curl >/dev/null 2>&1; then
  echo "[05] Installing curl..."
  apt-get update -y && apt-get install -y curl
fi
if [[ ! -f "$IMG_FILE" ]]; then
  echo "[05] Downloading Ubuntu 24.04 cloud image... ($IMG_URL)"
  curl -L "$IMG_URL" -o "$IMG_FILE"
fi

echo "[05] Creating cloud-init template VM $TEMPLATE_VM_ID..."
qm create $TEMPLATE_VM_ID --name ubuntu-2404-template --memory 1024 --cores 1 --net0 virtio,bridge=${VM_BR_LAN}
qm importdisk $TEMPLATE_VM_ID "$IMG_FILE" "$DISK_STORAGE"
qm set $TEMPLATE_VM_ID --scsihw virtio-scsi-pci --scsi0 ${DISK_STORAGE}:vm-${TEMPLATE_VM_ID}-disk-0
qm set $TEMPLATE_VM_ID --ide2 ${ISO_STORAGE}:cloudinit
qm set $TEMPLATE_VM_ID --boot c --bootdisk scsi0
qm set $TEMPLATE_VM_ID --serial0 socket --vga serial0
qm template $TEMPLATE_VM_ID
echo "[05] Template created (VMID=$TEMPLATE_VM_ID)."
