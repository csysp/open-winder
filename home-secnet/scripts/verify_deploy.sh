#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Run post-deploy verifications (wg, dns, isolation, ids, spa).
# Inputs: .env via scripts/lib/env.sh; VERBOSE (optional)
# Outputs: diagnostic logs
# Side effects: none

usage() {
  cat <<'USAGE'
Usage: verify_deploy.sh
  Runs non-destructive verification checks after deployment.

Environment:
  VERBOSE=1   Enable verbose logging
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi
# shellcheck source=scripts/lib/log.sh
# shellcheck source=home-secnet/scripts/lib/log.sh
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"
if [[ -f "$LIB_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$LIB_PATH"
fi

log_info "[12] Running post checks..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

ROUTER_IP=${ROUTER_IP:-}
if [[ -z "${ROUTER_IP}" ]]; then
  read -r -p "[12] Enter Router VM IP (for ssh): " ROUTER_IP
  if [[ -z "$ROUTER_IP" ]]; then echo "[12] Router IP required." >&2; exit 1; fi
fi

RUSER=${ROUTER_ADMIN_USER}

echo "[12] Check WireGuard status on router..."
ssh -o StrictHostKeyChecking=accept-new ${RUSER}@${ROUTER_IP} 'sudo wg show || { echo "wg show failed (WireGuard may be down)" >&2; exit 0; }'

echo "[12] Check DNS from router for each VLAN IP (binding tests)..."
ssh ${RUSER}@${ROUTER_IP} 'for ip in ${GW_TRUSTED} ${GW_IOT} ${GW_GUEST} ${GW_LAB}; do echo "Testing DNS bind on $ip"; if ! dig +short @${ip} example.com; then echo "DNS query failed on ${ip}" >&2; fi; done'

echo "[12] Verify Suricata running..."
ssh ${RUSER}@${ROUTER_IP} 'systemctl status suricata --no-pager || echo "suricata service not healthy" >&2; sudo tail -n 50 /var/log/suricata/suricata.log || echo "no suricata logs" >&2'

if [[ "${WRAP_MODE:-none}" == "hysteria2" ]]; then
  echo "[12] Check Hysteria2 (QUIC wrapper) status and port..."
  ssh ${RUSER}@${ROUTER_IP} "systemctl status hysteria --no-pager || echo 'hysteria service not healthy' >&2; sudo ss -lun | awk '{print \$5}' | grep -q ':${WRAP_LISTEN_PORT}\$' && echo 'Hysteria listening on UDP ${WRAP_LISTEN_PORT}' || echo 'Hysteria UDP ${WRAP_LISTEN_PORT} not found'"
fi

echo "[12] Next steps:"
echo " - Connect a peer using clients/wg-client1.conf (or QR)."
echo " - Move switch ports to VLANs: ${VLAN_TRUSTED}/${VLAN_IOT}/${VLAN_GUEST}/${VLAN_LAB}."
echo " - (Optional) Route Proxmox updates via Router WG egress."
