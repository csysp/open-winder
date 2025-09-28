#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Build a pinned OpenWRT image using ImageBuilder and overlay files from render/
# Inputs from .env (via lib/env.sh): OPENWRT_VERSION, OPENWRT_TARGET, OPENWRT_PROFILE, OPENWRT_SHA256
# Side effects: Downloads ImageBuilder tarball, verifies checksum, builds image to render/images/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${ROOT_DIR}/render/images"
TMP_ROOT="/tmp/winder-imagebuilder-$$"

# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"

require_vars OPENWRT_VERSION OPENWRT_TARGET OPENWRT_PROFILE OPENWRT_SHA256

IB_BASE="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${OPENWRT_TARGET}"
IB_NAME="openwrt-imagebuilder-${OPENWRT_VERSION}-${OPENWRT_TARGET}.Linux-x86_64"
IB_TGZ="${IB_NAME}.tar.xz"
IB_URL="${IB_BASE}/${IB_TGZ}"

log_info "[ib] Preparing ImageBuilder ${IB_NAME}"
mkdir -p "$OUT_DIR" "$TMP_ROOT"

command -v curl >/dev/null 2>&1 || { echo "missing curl" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "missing sha256sum" >&2; exit 1; }
command -v xz >/dev/null 2>&1 || { echo "missing xz-utils (xz)" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "missing tar" >&2; exit 1; }

TGZ_PATH="${TMP_ROOT}/${IB_TGZ}"
curl -fsSL "$IB_URL" -o "$TGZ_PATH"
GOT_SHA="$(sha256sum "$TGZ_PATH" | awk '{print $1}')"
if [[ "$GOT_SHA" != "$OPENWRT_SHA256" ]]; then
  echo "[ib] checksum mismatch for ImageBuilder" >&2
  echo "[ib] expected: $OPENWRT_SHA256" >&2
  echo "[ib] got:      $GOT_SHA" >&2
  exit 1
fi

log_info "[ib] Extracting ImageBuilder"
IB_DIR="${TMP_ROOT}/${IB_NAME}"
mkdir -p "$IB_DIR"
tar -xJf "$TGZ_PATH" -C "$TMP_ROOT"

pushd "$IB_DIR" >/dev/null

# Packages and files
EXTRA_PKGS="${OPENWRT_PACKAGES:-}"  # optional space-separated list in .env
# Auto-append Suricata if enabled
if [[ "${SURICATA_ENABLE:-false}" == "true" ]]; then
  case " $EXTRA_PKGS " in
    *" suricata "*) : ;; 
    *) echo "[ib] SURICATA_ENABLE=true → adding 'suricata' to OPENWRT_PACKAGES"; EXTRA_PKGS="${EXTRA_PKGS} suricata" ;;
  esac
fi
FILES_DIR="${ROOT_DIR}/render/openwrt-files"
# Prepare a minimal files/ overlay from rendered OpenWRT artifacts only
mkdir -p "$FILES_DIR"
if [[ -d "${ROOT_DIR}/render/openwrt" ]]; then
  rsync -a "${ROOT_DIR}/render/openwrt/" "$FILES_DIR/"
fi

log_info "[ib] Building image for PROFILE=${OPENWRT_PROFILE}"
make image PROFILE="${OPENWRT_PROFILE}" PACKAGES="$EXTRA_PKGS" FILES="$FILES_DIR"

mkdir -p "$OUT_DIR"
find bin/targets -type f \( -name "*.img*" -o -name "*.iso*" -o -name "*sysupgrade*" \) -exec cp -f {} "$OUT_DIR/" \;

popd >/dev/null
rm -rf "$TMP_ROOT"
log_info "[ib] Build complete. Images in: $OUT_DIR"
