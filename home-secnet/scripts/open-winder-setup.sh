#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: One-click orchestration for Winder (OpenWRT-only)
# Runs: wizard -> render -> build -> optional flash (destructive)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"

YES=0
FLASH=0
FLASH_ARGS=()

usage(){
  cat <<USAGE
Usage: open-winder-setup.sh [--yes] [--flash device=/dev/sdX]
  --yes                  Non-interactive where safe
  --flash device=PATH    Flash newest built image to device (destructive)
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --flash*) FLASH=1; FLASH_ARGS+=("$arg") ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage; exit 1 ;;
  esac
done

log_info "[setup] Starting wizard..."
if [[ "$YES" -eq 1 ]]; then
  "${SCRIPT_DIR}/install.sh" --yes
else
  "${SCRIPT_DIR}/install.sh"
fi

log_info "[setup] Rendering overlay..."
make -C "${ROOT_DIR}" openwrt-render

log_info "[setup] Building image (pinned ImageBuilder)..."
make -C "${ROOT_DIR}" openwrt-build

if [[ "$FLASH" -eq 1 ]]; then
  img=$(ls -1t "${ROOT_DIR}/render/images"/* 2>/dev/null | head -n1 || true)
  if [[ -z "$img" ]]; then
    echo "[setup] No built images found under render/images/." >&2
    exit 1
  fi
  # Expect arg like: --flash device=/dev/sdX
  dev=""
  for a in "${FLASH_ARGS[@]}"; do
    if [[ "$a" == device=* ]]; then dev="${a#device=}"; fi
  done
  if [[ -z "$dev" ]]; then
    echo "[oneclick] --flash requires device=/dev/sdX" >&2; exit 1
  fi
  log_info "[setup] Flashing $img to $dev (destructive)..."
  make -C "${ROOT_DIR}" openwrt-flash device="$dev" image="$img"
fi

log_info "[setup] Done. Images: ${ROOT_DIR}/render/images/"
