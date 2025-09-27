#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Preview baremetal network config changes (non-destructive)
# Inputs: .env
# Outputs: Suggested netplan/systemd-networkd snippets

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

apply=${1:-}

has() { command -v "$1" >/dev/null 2>&1; }

echo "[host:bmetal] Network configuration"
echo "  WAN IF: ${ROUTER_WAN_IF:-<unset>} (mode: ${ISP_WAN_TYPE:-dhcp})"
echo "  LAN IF: ${ROUTER_LAN_IF:-<unset>}"
if [[ "${ISP_WAN_TYPE:-dhcp}" == "static" ]]; then
  echo "  WAN static: ${WAN_STATIC_IP:-} gw ${WAN_STATIC_GW:-} dns ${WAN_STATIC_DNS:-}"
fi

if [[ "$apply" != "--apply" ]]; then
  echo "[host:bmetal] Preview only. Run with --apply to write netplan and apply safely."
  exit 0
fi

if ! has netplan; then
  echo "[host:bmetal] netplan not found; cannot apply. Install netplan.io or configure manually." >&2
  exit 1
fi

mapfile -t nics < <(ls -1 /sys/class/net | grep -vE '^(lo|wg|docker|veth)' | sort)
select_if() {
  local prompt="$1"; shift
  local -n out=$1
  echo "$prompt" >&2
  local i=1
  for nic in "${nics[@]}"; do echo "  [$i] $nic"; ((i++)); done
  local sel
  while true; do
    read -r -p "Select [1-${#nics[@]}]: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#nics[@]} )); then
      out=${nics[$((sel-1))]}
      break
    fi
  done
}

wan_if="${ROUTER_WAN_IF:-}"
lan_if="${ROUTER_LAN_IF:-}"
if [[ -z "$wan_if" || -z "$lan_if" || "$wan_if" == "$lan_if" ]]; then
  select_if "Select WAN interface:" wan_if
  select_if "Select LAN interface:" lan_if
  if [[ "$wan_if" == "$lan_if" ]]; then
    echo "WAN and LAN must differ" >&2; exit 1
  fi
fi

ts=$(date +%Y%m%d%H%M%S)
sudo mkdir -p /etc/netplan
for f in /etc/netplan/*.yaml; do [[ -f "$f" ]] && sudo cp -f "$f" "$f.bak-$ts" || true; done

cidr_to_prefix() { awk -F/ '{print $2}' <<<"$1"; }
trusted_prefix=$(cidr_to_prefix "${NET_TRUSTED:-10.20.0.0/24}")
outfile=/etc/netplan/99-winder.yaml
sudo tee "$outfile" >/dev/null <<YAML
network:
  version: 2
  renderer: networkd
  ethernets:
    $wan_if:
      dhcp4: ${ISP_WAN_TYPE:-dhcp}
      optional: true
    $lan_if:
      dhcp4: false
  bridges:
    br0:
      interfaces: [$lan_if]
      addresses: [${GW_TRUSTED:-10.20.0.1}/$trusted_prefix]
      dhcp4: false
      parameters:
        stp: false
        forward-delay: 0
YAML

echo "[host:bmetal] Wrote $outfile; attempting 'netplan try' (120s rollback)…"
sudo netplan generate
sudo netplan try --timeout 120 || { echo "netplan try aborted or failed" >&2; exit 1; }
echo "[host:bmetal] Netplan applied."
