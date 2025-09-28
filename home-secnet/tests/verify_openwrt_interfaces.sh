#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Ensure LAN_IF and WAN_IF are rendered (non-empty) in OpenWRT configs when .env is populated.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Prepare minimal env for render
export ROUTER_LAN_IF="br-lan"
export ROUTER_WAN_IF="wan"

"$ROOT_DIR/scripts/render_router_configs.sh" >/dev/null 2>&1 || true

cfg_net="$ROOT_DIR/render/openwrt/etc/config/network"

if [[ ! -f "$cfg_net" ]]; then
  echo "[verify] network config not rendered at $cfg_net" >&2
  exit 1
fi

lan_val=$(grep -E "option +device +'?br-lan'?" -i "$cfg_net" || true)
wan_val=$(grep -E "config +interface +'?wan'?|option +device +'?wan'?" -i "$cfg_net" || true)

if [[ -z "$lan_val" ]]; then
  echo "[verify] LAN_IF did not render into network config" >&2
  exit 1
fi
if [[ -z "$wan_val" ]]; then
  echo "[verify] WAN_IF did not render into network config" >&2
  exit 1
fi

echo "[verify] OpenWRT interfaces rendered (LAN_IF/WAN_IF present)."

