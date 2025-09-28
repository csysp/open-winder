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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"

log_info "[12] Running post checks..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

RUSER=${ROUTER_ADMIN_USER}
ROUTER_IP=${ROUTER_IP:-}

is_local_router() {
  local rip="${ROUTER_IP:-}"
  if [[ -z "$rip" || "$rip" == "127.0.0.1" || "$rip" == "localhost" ]]; then return 0; fi
  ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -qx "$rip" && return 0 || return 1
}

run_remote() { ssh -o StrictHostKeyChecking=accept-new "${RUSER}@${ROUTER_IP}" "$@"; }
run_local()  { bash -lc "$*"; }

if is_local_router; then
  log_info "[12] Local router detected; running checks locally"
  run_local "sudo wg show || { echo 'wg show failed (WireGuard may be down)' >&2; exit 0; }"
  run_local 'for ip in ${GW_TRUSTED} ${GW_IOT} ${GW_GUEST} ${GW_LAB}; do echo "Testing DNS bind on $ip"; if ! dig +short @${ip} example.com; then echo "DNS query failed on ${ip}" >&2; fi; done'
  if [[ "${IDS_MODE:-suricata}" != "none" ]]; then
    run_local 'systemctl status suricata --no-pager || echo "suricata service not healthy" >&2; sudo tail -n 50 /var/log/suricata/suricata.log || echo "no suricata logs" >&2'
  fi
  if [[ "${WRAP_MODE:-none}" == "hysteria2" ]]; then
    run_local "systemctl status hysteria --no-pager || echo 'hysteria service not healthy' >&2; sudo ss -lun | awk '{print \\$5}' | grep -q ':${WRAP_LISTEN_PORT}\$' && echo 'Hysteria listening on UDP ${WRAP_LISTEN_PORT}' || echo 'Hysteria UDP ${WRAP_LISTEN_PORT} not found'"
  fi
else
  if [[ -z "${ROUTER_IP}" ]]; then
    read -r -p "[12] Enter Router VM IP (for ssh): " ROUTER_IP
    if [[ -z "$ROUTER_IP" ]]; then echo "[12] Router IP required." >&2; exit 1; fi
  fi
  log_info "[12] Using SSH to run remote checks"
  run_remote 'sudo wg show || { echo "wg show failed (WireGuard may be down)" >&2; exit 0; }'
  run_remote 'for ip in ${GW_TRUSTED} ${GW_IOT} ${GW_GUEST} ${GW_LAB}; do echo "Testing DNS bind on $ip"; if ! dig +short @${ip} example.com; then echo "DNS query failed on ${ip}" >&2; fi; done'
  if [[ "${IDS_MODE:-suricata}" != "none" ]]; then
    run_remote 'systemctl status suricata --no-pager || echo "suricata service not healthy" >&2; sudo tail -n 50 /var/log/suricata/suricata.log || echo "no suricata logs" >&2'
  fi
  if [[ "${WRAP_MODE:-none}" == "hysteria2" ]]; then
    run_remote "systemctl status hysteria --no-pager || echo 'hysteria service not healthy' >&2; sudo ss -lun | awk '{print \\$5}' | grep -q ':${WRAP_LISTEN_PORT}\$' && echo 'Hysteria listening on UDP ${WRAP_LISTEN_PORT}' || echo 'Hysteria UDP ${WRAP_LISTEN_PORT} not found'"
  fi
fi

echo "[12] Next steps:"
echo " - Connect a peer using clients/wg-client1.conf (or QR)."
echo " - Move switch ports to VLANs: ${VLAN_TRUSTED}/${VLAN_IOT}/${VLAN_GUEST}/${VLAN_LAB}."
echo " - (Optional) Route Proxmox updates via Router WG egress."
