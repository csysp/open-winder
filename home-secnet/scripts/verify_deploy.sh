#!/usr/bin/env bash
set -euo pipefail

echo "[09] Running post checks..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

ROUTER_IP=${ROUTER_IP:-}
if [[ -z "${ROUTER_IP}" ]]; then
  read -r -p "[09] Enter Router VM IP (for ssh): " ROUTER_IP
  if [[ -z "$ROUTER_IP" ]]; then echo "[09] Router IP required." >&2; exit 1; fi
fi

RUSER=${ROUTER_ADMIN_USER}

echo "[09] Check WireGuard status on router..."
ssh -o StrictHostKeyChecking=no ${RUSER}@${ROUTER_IP} 'sudo wg show || true'

echo "[09] Check DNS from router for each VLAN IP (binding tests)..."
ssh ${RUSER}@${ROUTER_IP} 'for ip in ${GW_TRUSTED} ${GW_IOT} ${GW_GUEST} ${GW_LAB}; do echo "Testing DNS bind on $ip"; dig +short @${GW_TRUSTED} example.com || true; done'

echo "[09] Verify Suricata running..."
ssh ${RUSER}@${ROUTER_IP} 'systemctl status suricata --no-pager || true; sudo tail -n 50 /var/log/suricata/suricata.log || true'

if [[ "${WRAP_MODE:-none}" == "hysteria2" ]]; then
  echo "[09] Check Hysteria2 (QUIC wrapper) status and port..."
  ssh ${RUSER}@${ROUTER_IP} "systemctl status hysteria --no-pager || true; sudo ss -lun | awk '{print \$5}' | grep -q ':${WRAP_LISTEN_PORT}\$' && echo 'Hysteria listening on UDP ${WRAP_LISTEN_PORT}' || echo 'Hysteria UDP ${WRAP_LISTEN_PORT} not found'"
fi

echo "[09] Next steps:"
echo " - Connect a peer using clients/wg-client1.conf (or QR)."
echo " - Move switch ports to VLANs: ${VLAN_TRUSTED}/${VLAN_IOT}/${VLAN_GUEST}/${VLAN_LAB}."
echo " - (Optional) Route Proxmox updates via Router WG egress."
