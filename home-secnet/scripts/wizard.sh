#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Dynamic, strict-mode-safe wizard for OpenWRT-only Winder setup.
# Inputs: --yes (optional)
# Side effects: Creates/updates .env, optional hypervisor bridges, renders overlay.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"    # enforces MODE=openwrt

YES=0
if [[ "${1:-}" == "--yes" ]]; then YES=1; fi

log_info "[wiz] Winder OpenWRT setup wizard starting..."

# 1) Preflight (read-only unless packages are missing; we only warn here)
if ! command -v rg >/dev/null 2>&1; then log_warn "[wiz] ripgrep (rg) not found; lint checks may be limited"; fi
for cmd in bash curl rsync ssh nft wg; do
  command -v "$cmd" >/dev/null 2>&1 || log_warn "[wiz] Missing tool: $cmd"
done

# 2) Environment wizard (reuses setup_env.sh for atomic, idempotent writes)
log_info "[wiz] Preparing .env via setup_env.sh"
"${SCRIPT_DIR}/setup_env.sh"

# Reload env after setup
set +u
# shellcheck disable=SC1090
[[ -f "${ROOT_DIR}/.env" ]] && source "${ROOT_DIR}/.env"
set -u

# 3) Optional: hypervisor bridge setup if Proxmox detected
if command -v pveversion >/dev/null 2>&1; then
  if [[ "$YES" -eq 1 ]]; then ans="y"; else read -r -p "[wiz] Proxmox detected. Configure vmbr0/vmbr1 now? [y/N] " ans; fi
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    sudo "${SCRIPT_DIR}/providers/proxmox/configure_bridges.sh" YES=1 || {
      log_warn "[wiz] Bridge setup failed or was skipped."; }
  else
    log_info "[wiz] Skipping Proxmox bridge setup."
  fi
fi

# 4) Render overlay artifacts
log_info "[wiz] Rendering router overlay artifacts..."
"${SCRIPT_DIR}/render_router_configs.sh"

log_info "[wiz] Done. Rendered artifacts live under: ${ROOT_DIR}/render"
echo "Next steps:"
echo "- Build OpenWRT image (if not already): make -C home-secnet openwrt-build"
echo "- Flash image to device:           make -C home-secnet openwrt-flash device=/dev/sdX image=<path>"
echo "- Or push configs to a VM/router host: home-secnet/scripts/apply_router_configs.sh"

