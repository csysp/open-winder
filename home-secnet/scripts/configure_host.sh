#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Dispatch host configuration based on HOST_PROVIDER
# Inputs: .env (HOST_PROVIDER)
# Outputs: provider-specific actions (non-destructive for baremetal)
# Side effects: provider-dependent

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

HOST_PROVIDER="${HOST_PROVIDER:-baremetal}"

case "$HOST_PROVIDER" in
  proxmox)
    bash "$ROOT_DIR/scripts/providers/proxmox/configure_bridges.sh"
    bash "$ROOT_DIR/scripts/providers/proxmox/create_router_vm.sh"
    bash "$ROOT_DIR/scripts/providers/proxmox/apply_node_firewall.sh"
    ;;
  baremetal)
    bash "$ROOT_DIR/scripts/providers/baremetal/configure_network.sh"
    bash "$ROOT_DIR/scripts/providers/baremetal/host_firewall.sh"
    ;;
  *)
    echo "Unknown HOST_PROVIDER='$HOST_PROVIDER'" >&2
    exit 1
    ;;
esac

