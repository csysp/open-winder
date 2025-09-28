#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
backup=""
if [[ -f "$ENV_FILE" ]]; then backup="${ENV_FILE}.bak$$"; cp -f "$ENV_FILE" "$backup"; fi
cat >"$ENV_FILE" <<EOF
MODE=openwrt
SURICATA_ENABLE=true
ROUTER_LAN_IF=br-lan
ROUTER_WAN_IF=wan
EOF

VERBOSE=1 bash "$ROOT_DIR/scripts/render_router_configs.sh" || true

cfg="$ROOT_DIR/render/openwrt/etc/suricata/suricata.yaml"
if [[ ! -f "$cfg" ]]; then
  echo "[verify] Suricata overlay missing at $cfg" >&2
  if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  exit 1
fi
echo "[verify] Suricata overlay present."
if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi

