#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Purpose: Flash a built OpenWRT image to a block device (destructive)
# Inputs: path to image (or auto-detect latest), target device, --yes to confirm

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES_DIR="$ROOT_DIR/render/openwrt/image"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --device /dev/sdX [--image <path>] [--yes]
Flashes the specified OpenWRT image to the target device. Destructive.
USAGE
}

DEVICE=""
IMAGE=""
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2;;
    --image) IMAGE="$2"; shift 2;;
    --yes) YES=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

[[ -b "$DEVICE" ]] || { echo "Target device not found: $DEVICE" >&2; exit 1; }

if [[ -z "$IMAGE" ]]; then
  IMAGE="$(find "$IMAGES_DIR" -maxdepth 1 -type f -name "*.img*" -print0 2>/dev/null | xargs -0 ls -1t 2>/dev/null | head -n1 || true)"
fi
[[ -f "$IMAGE" ]] || { echo "Image not found: $IMAGE" >&2; exit 1; }

echo "About to write $IMAGE to $DEVICE (this will erase it)."
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Proceed? type 'yes' to continue: " CONFIRM || true
  [[ "$CONFIRM" == "yes" ]] || { echo "Aborted"; exit 1; }
fi

sync
if command -v pv >/dev/null 2>&1; then
  pv "$IMAGE" | dd of="$DEVICE" bs=4M conv=fsync status=progress
else
  dd if="$IMAGE" of="$DEVICE" bs=4M conv=fsync status=progress
fi
sync
echo "Done. You can now boot from $DEVICE."
