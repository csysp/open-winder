#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"
ROUTER_IP=${ROUTER_IP:-}
[[ -z "${ROUTER_IP}" ]] && { echo "Set ROUTER_IP" >&2; exit 1; }
ssh -o StrictHostKeyChecking=no "${ROUTER_ADMIN_USER}"@"${ROUTER_IP}" 'sudo systemctl is-active suricata && sudo tail -n 5 /var/log/suricata/eve.json || true'
echo "Suricata status checked."
