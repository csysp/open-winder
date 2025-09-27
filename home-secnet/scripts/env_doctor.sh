#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Validate .env for common issues (CIDRs, ports, interfaces)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then echo ".env not found at $ENV_FILE" >&2; exit 1; fi
# shellcheck disable=SC1090
source "$ENV_FILE"

fail=0

req_vars=( ISP_WAN_TYPE ROUTER_WAN_IF ROUTER_LAN_IF GW_TRUSTED NET_TRUSTED WG_PORT )
for v in "${req_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then echo "[env] missing $v" >&2; fail=1; fi
done

valid_cidr() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; }
valid_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( $1>0 && $1<65536 )); }

if [[ -n "${NET_TRUSTED:-}" ]] && ! valid_cidr "$NET_TRUSTED"; then echo "[env] NET_TRUSTED not CIDR: $NET_TRUSTED" >&2; fail=1; fi
if [[ -n "${GW_TRUSTED:-}" ]] && ! valid_ip "$GW_TRUSTED"; then echo "[env] GW_TRUSTED not IPv4: $GW_TRUSTED" >&2; fail=1; fi
if [[ -n "${WG_PORT:-}" ]] && ! valid_port "$WG_PORT"; then echo "[env] WG_PORT invalid: $WG_PORT" >&2; fail=1; fi

if [[ -d /sys/class/net ]]; then
  for ifn in "$ROUTER_WAN_IF" "$ROUTER_LAN_IF"; do
    [[ -e "/sys/class/net/$ifn" ]] || { echo "[env] interface missing: $ifn" >&2; fail=1; }
  done
fi

if (( fail )); then
  echo "[env] issues found. Please fix above and retry." >&2
  exit 1
fi

echo "[env] OK"

