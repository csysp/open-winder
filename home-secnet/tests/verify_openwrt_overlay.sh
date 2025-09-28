#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Purpose: Quick sanity checks for rendered OpenWRT overlay

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="$ROOT_DIR/render/openwrt/overlay"

if [[ ! -d "$OVERLAY_DIR" ]]; then
  echo "overlay missing; run scripts/render_openwrt_overlay.sh" >&2
  exit 1
fi

required=(
  etc/config/network
  etc/config/firewall
  etc/config/dhcp
  etc/config/system
  etc/nftables.d/99-wg-spa.nft
  etc/init.d/spa-pq
  etc/adguardhome.yaml
  etc/unbound/unbound.conf
)

for rel in "${required[@]}"; do
  [[ -f "$OVERLAY_DIR/$rel" ]] || { echo "missing: $rel" >&2; exit 1; }
done

grep -q 'udp dport' "$OVERLAY_DIR/etc/nftables.d/99-wg-spa.nft" || { echo "nft gate seems incomplete" >&2; exit 1; }

echo "Overlay sanity OK"

