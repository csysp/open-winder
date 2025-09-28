#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Purpose: Build OpenWRT firmware using pinned ImageBuilder and rendered overlay
# Inputs: .env (OPENWRT_VERSION, OPENWRT_TARGET, OPENWRT_PROFILE, OPENWRT_IB_SHA256 optional)
# Outputs: images under home-secnet/render/openwrt/image/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT_DIR/scripts/lib"
OUT_DIR="$ROOT_DIR/render/openwrt/image"
OVERLAY_DIR="$ROOT_DIR/render/openwrt/overlay"
WORK_DIR="/tmp/winder-openwrt-ib-$$"

# shellcheck disable=SC1090
source "$LIB_DIR/log.sh"
# shellcheck disable=SC1090
source "$LIB_DIR/env.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--prepare-only]
Build OpenWRT image: downloads ImageBuilder (pinned), verifies checksum (optional),
and composes firmware with FILES overlay pointing to render/openwrt/overlay.

Requires the overlay to exist (run render_openwrt_overlay.sh first).
USAGE
}

PREPARE_ONLY=0
if [[ ${1:-} == "--help" ]]; then usage; exit 0; fi
if [[ ${1:-} == "--prepare-only" ]]; then PREPARE_ONLY=1; fi

load_env
OPENWRT_VERSION="${OPENWRT_VERSION:-23.05.4}"
OPENWRT_TARGET="${OPENWRT_TARGET:-x86/64}"
OPENWRT_PROFILE="${OPENWRT_PROFILE:-generic}"
OPENWRT_IB_SHA256="${OPENWRT_IB_SHA256:-}"

[[ -d "$OVERLAY_DIR" ]] || die 1 "overlay not found, run render_openwrt_overlay.sh first"
mkdir -p "$OUT_DIR"
mkdir -p "$WORK_DIR"

# ImageBuilder URL pattern
TARGET_DIR="${OPENWRT_TARGET%%/*}"
SUBTARGET_DIR="${OPENWRT_TARGET##*/}"
IB_TARBALL="openwrt-imagebuilder-${OPENWRT_VERSION}-${OPENWRT_TARGET}.Linux-x86_64.tar.xz"
IB_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET_DIR}/${SUBTARGET_DIR}/${IB_TARBALL}"

log_info "Fetching ImageBuilder ${OPENWRT_VERSION} for ${OPENWRT_TARGET}"
curl -fL "${IB_URL}" -o "$WORK_DIR/${IB_TARBALL}"

if [[ -n "$OPENWRT_IB_SHA256" ]]; then
  echo "${OPENWRT_IB_SHA256}  ${WORK_DIR}/${IB_TARBALL}" | sha256sum -c - || die 1 "SHA256 mismatch for ImageBuilder"
  log_info "ImageBuilder checksum OK"
else
  log_warn "OPENWRT_IB_SHA256 not set; skipping checksum (set for reproducibility)"
fi

tar -C "$WORK_DIR" -xf "$WORK_DIR/${IB_TARBALL}"
IB_DIR="$WORK_DIR/${IB_TARBALL%.tar.xz}"

# Base package set (adjust per needs)
PACKAGES=(
  ca-bundle ca-certificates
  block-mount kmod-usb-storage
  kmod-wireguard wireguard-tools
  nftables kmod-nft-core kmod-nft-offload
  adguardhome unbound-daemon unbound-control
  suricata
)

if [[ "${IDS_ENABLE:-false}" != "true" ]]; then
  # Remove suricata if disabled
  PACKAGES=("${PACKAGES[@]/suricata}")
fi

EXTRA_PACKAGES_STR="${EXTRA_PACKAGES:-}"
PACKAGES_STR="${PACKAGES[*]} ${EXTRA_PACKAGES_STR}"

log_info "Composing image (PROFILE=${OPENWRT_PROFILE})"
make -C "$IB_DIR" image \
  PROFILE="$OPENWRT_PROFILE" \
  PACKAGES="$PACKAGES_STR" \
  FILES="$OVERLAY_DIR"

if [[ "$PREPARE_ONLY" == 1 ]]; then
  log_info "Prepare-only complete"
  exit 0
fi

find "$IB_DIR/bin/targets" -type f -maxdepth 4 -printf '%P\n' > "$OUT_DIR/manifest.txt"
cp -a "$IB_DIR/bin/targets"/*/*/* "$OUT_DIR/" || true

log_info "Build complete; images in $OUT_DIR"
ls -lh "$OUT_DIR" || true

