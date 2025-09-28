#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
backup=""
if [[ -f "$ENV_FILE" ]]; then backup="${ENV_FILE}.bak$$"; cp -f "$ENV_FILE" "$backup"; fi
cat >"$ENV_FILE" <<EOF
MODE=openwrt
WRAP_MODE=hysteria2
WRAP_LISTEN_PORT=443
WRAP_PASSWORD=testpass123
WG_PORT=51820
EOF

VERBOSE=1 bash "$ROOT_DIR/scripts/render_router_configs.sh" || true

cfg="$ROOT_DIR/render/openwrt/etc/hysteria/config.yaml"
svc="$ROOT_DIR/render/openwrt/etc/init.d/hysteria"
nft="$ROOT_DIR/render/openwrt/etc/nftables.d/20-hysteria.nft"
if [[ ! -f "$cfg" || ! -f "$svc" || ! -f "$nft" ]]; then
  echo "[verify] Hysteria overlay missing (cfg=$([[ -f "$cfg" ]] && echo ok || echo missing), svc=$([[ -f "$svc" ]] && echo ok || echo missing), nft=$([[ -f "$nft" ]] && echo ok || echo missing))" >&2
  if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  exit 1
fi
echo "[verify] Hysteria overlay present."
if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi

