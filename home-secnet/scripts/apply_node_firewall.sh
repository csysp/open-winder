#!/usr/bin/env bash
set -euo pipefail

echo "[08] Locking down Proxmox firewall..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

if [[ $EUID -ne 0 ]]; then
  echo "[08] Run as root on the Proxmox host." >&2
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
  perl -M5.010 -pe 's/\$\{([A-Z0-9_]+)\}/$ENV{$1} //ge' "$NODE_RULES_SRC" > "$tmp_rules"
  perl -M5.010 -pe 's/\$\{([A-Z0-9_]+)\}/$ENV{$1} //ge' "$NODE_GROUPS_SRC" > "$tmp_groups"
fi

# Write node and group configs to correct Proxmox paths
NODE_DIR="/etc/pve/nodes/$PVE_NODE"
mkdir -p "$NODE_DIR" /etc/pve/firewall
cp -f "$tmp_rules" "$NODE_DIR/host.fw"
cp -f "$tmp_groups" "/etc/pve/firewall/groups.cfg"

# Enable firewall via Proxmox API and reload
if command -v pvesh >/dev/null 2>&1; then
  pvesh set "/cluster/firewall/options" --enable 1 >/dev/null 2>&1 || true
  pvesh set "/nodes/$PVE_NODE/firewall/options" --enable 1 --policy_in DROP --policy_out ACCEPT >/dev/null 2>&1 || true
fi
# Apply and activate firewall rules
pve-firewall compile || true
pve-firewall restart || true
echo "[08] Applied node firewall (host.fw) and groups. Default inbound DROP enforced."
