#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Apply Proxmox node firewall lockdown.
# Inputs: .env via scripts/lib/env.sh; VERBOSE (optional)
# Outputs: none
# Side effects: Modifies pve-firewall rules.

usage() {
  cat <<'USAGE'
Usage: apply_node_firewall.sh
  Applies node-level firewall policy on Proxmox host.

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

log_info "[10] Locking down Proxmox firewall..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Load env and export for envsubst compatibility
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"
set -a; load_env; set +a

if [[ $EUID -ne 0 ]]; then
  echo "[10] Run as root on the Proxmox host." >&2
  exit 1
fi

# Resolve dynamic PVE_NODE if left as $(hostname) in .env
if [[ -z "${PVE_NODE:-}" || "$PVE_NODE" == '$(hostname)' ]]; then
  PVE_NODE=$(hostname)
fi

NODE_RULES_SRC="$ROOT_DIR/proxmox/node-firewall.rules"
NODE_GROUPS_SRC="$ROOT_DIR/proxmox/node-firewall.groups"

# Render variables into firewall files
tmp_rules=$(mktemp)
tmp_groups=$(mktemp)
trap 'rm -f "$tmp_rules" "$tmp_groups"' EXIT
if command -v envsubst >/dev/null 2>&1; then
  envsubst < "$NODE_RULES_SRC" > "$tmp_rules"
  envsubst < "$NODE_GROUPS_SRC" > "$tmp_groups"
else
  perl -M5.010 -pe 's/\$\{([A-Z0-9_]+)\}/defined $ENV{$1} ? $ENV{$1} : ""/ge' "$NODE_RULES_SRC" > "$tmp_rules"
  perl -M5.010 -pe 's/\$\{([A-Z0-9_]+)\}/defined $ENV{$1} ? $ENV{$1} : ""/ge' "$NODE_GROUPS_SRC" > "$tmp_groups"
fi

# Write node and group configs to correct Proxmox paths
NODE_DIR="/etc/pve/nodes/$PVE_NODE"
mkdir -p "$NODE_DIR" /etc/pve/firewall
cp -f "$tmp_rules" "$NODE_DIR/host.fw"
cp -f "$tmp_groups" "/etc/pve/firewall/groups.cfg"

# Enable firewall via Proxmox API and reload
if command -v pvesh >/dev/null 2>&1; then
  pvesh set "/cluster/firewall/options" --enable 1 >/dev/null 2>&1 || log_warn "[10] Could not enable cluster firewall options"
  pvesh set "/nodes/$PVE_NODE/firewall/options" --enable 1 --policy_in DROP --policy_out ACCEPT >/dev/null 2>&1 || log_warn "[10] Could not enable node firewall or set policies"
fi
# Apply and activate firewall rules
pve-firewall compile || log_warn "[10] pve-firewall compile failed"
pve-firewall restart || log_warn "[10] pve-firewall restart failed"
echo "[10] Applied node firewall (host.fw) and groups. Default inbound DROP enforced."
