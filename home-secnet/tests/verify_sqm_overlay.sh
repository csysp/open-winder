#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
backup=""
if [[ -f "$ENV_FILE" ]]; then backup="${ENV_FILE}.bak$$"; cp -f "$ENV_FILE" "$backup"; fi
cat >"$ENV_FILE" <<EOF
MODE=openwrt
SHAPING_ENABLE=true
SQM_INTERFACE=wan
SHAPING_EGRESS_KBIT=10000
SHAPING_INGRESS_KBIT=50000
EOF

VERBOSE=1 bash "$ROOT_DIR/scripts/render_router_configs.sh" || true

cfg="$ROOT_DIR/render/openwrt/etc/config/sqm"
if [[ ! -f "$cfg" ]]; then
  echo "[verify] SQM config missing at $cfg" >&2
  if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  exit 1
fi
echo "[verify] SQM overlay present."
if [[ -n "$backup" ]]; then mv -f "$backup" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi

