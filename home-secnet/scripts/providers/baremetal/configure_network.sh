#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Preview baremetal network config changes (non-destructive)
# Inputs: .env
# Outputs: Suggested netplan/systemd-networkd snippets

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

echo "[host:bmetal] Preview network configuration (no changes applied)."
echo "  WAN IF: ${ROUTER_WAN_IF:-<unset>} (mode: ${ISP_WAN_TYPE:-dhcp})"
echo "  LAN IF: ${ROUTER_LAN_IF:-<unset>}"
if [[ "${ISP_WAN_TYPE:-dhcp}" == "static" ]]; then
  echo "  WAN static: ${WAN_STATIC_IP:-} gw ${WAN_STATIC_GW:-} dns ${WAN_STATIC_DNS:-}"
fi
echo "  To automate host networking, add a --apply mode later."

