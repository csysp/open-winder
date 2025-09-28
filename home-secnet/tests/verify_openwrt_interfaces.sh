#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Ensure LAN_IF and WAN_IF are rendered (non-empty) in OpenWRT configs when .env is populated.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Prepare minimal .env for render (simulate real flow)
ENV_FILE="$ROOT_DIR/.env"
backup=""
if [[ -f "$ENV_FILE" ]]; then backup="${ENV_FILE}.bak$$"; cp -f "$ENV_FILE" "$backup"; fi
cat >"$ENV_FILE" <<EOF
MODE=openwrt
ROUTER_LAN_IF=br-lan
ROUTER_WAN_IF=wan
WG_PORT=51820
WG_SERVER_PRIVKEY=dummykey
WG_SERVER_IP=10.0.0.1/24
EOF

"$ROOT_DIR/scripts/render_router_configs.sh" >/dev/null 2>&1 || true

cfg_net="$ROOT_DIR/render/openwrt/etc/config/network"

if [[ ! -f "$cfg_net" ]]; then
  echo "[verify] network config not rendered at $cfg_net" >&2
  echo "[verify][debug] ROOT_DIR=$ROOT_DIR" >&2
  echo "[verify][debug] Listing rendered files under render/:" >&2
  find "$ROOT_DIR/render" -maxdepth 4 -type f -print >&2 || true
  echo "[verify][debug] Available templates:" >&2
  find "$ROOT_DIR/openwrt/templates/etc/config" -maxdepth 1 -type f -print >&2 || true
  # restore env and fail
  if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  exit 1
fi

lan_val=$(grep -E "option +device +'?br-lan'?" -i "$cfg_net" || true)
wan_val=$(grep -E "config +interface +'?wan'?|option +device +'?wan'?" -i "$cfg_net" || true)

if [[ -z "$lan_val" ]]; then
  echo "[verify] LAN_IF did not render into network config" >&2
  if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  exit 1
fi
if [[ -z "$wan_val" ]]; then
  echo "[verify] WAN_IF did not render into network config" >&2
  if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  exit 1
fi

echo "[verify] OpenWRT interfaces rendered (LAN_IF/WAN_IF present)."

# restore env
if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
