#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"; [[ -f "$LIB_PATH" ]] && source "$LIB_PATH"

log_info "[00] Validating host environment (Linux + Proxmox + tools)..."

if [[ "$(uname -s)" != "Linux" ]]; then
  log_error "[00] This project targets Linux (Debian/Ubuntu)."
  exit 1
fi

need_root() {
  if [[ $EUID -ne 0 ]]; then
  log_error "[00] Run as root for package installation."
    exit 1
  fi
}

has() { command -v "$1" >/dev/null 2>&1; }

# Detect package manager
if ! has apt-get; then
  log_error "[00] Unsupported distro (requires apt)."
  exit 1
fi

req_bins=(curl rsync ssh bash nft wg envsubst perl openssl)
miss=()
for b in "${req_bins[@]}"; do
  if ! has "$b"; then miss+=("$b"); fi
done

if (( ${#miss[@]} )); then
  log_warn "[00] Missing tools: ${miss[*]}"
  need_root
  log_info "[00] Installing required packages..."
  apt-get update -y
  # Map common names to Debian packages
  apt-get install -y curl rsync openssh-client nftables wireguard-tools gettext-base perl openssl || true
fi

# Proxmox checks (optional but recommended)
if ! has qm; then
  log_warn "[00] Proxmox 'qm' not found. These scripts expect to run on a Proxmox host."
fi
if ! has pve-firewall; then
  log_warn "[00] Proxmox 'pve-firewall' not found. Node firewall step may be skipped."
fi

log_info "[00] OK."
