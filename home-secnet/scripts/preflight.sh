#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Validate host OS and required tools; install missing deps on Debian/Ubuntu.
# Inputs: environment variables: VERBOSE (optional)
# Outputs: none
# Side effects: May install packages via apt; exits non-zero on failure.

usage() {
  cat <<'USAGE'
Usage: preflight.sh
  Validates host (Linux + apt) and required tools. Installs missing packages when run as root.

Environment:
  VERBOSE=1   Enable verbose command logging
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
  if ! apt-get update -y; then
    die 1 "[00] 'apt-get update' failed; fix networking/apt and rerun"
  fi
  # Map common names to Debian packages
  if ! apt-get install -y curl rsync openssh-client nftables wireguard-tools gettext-base perl openssl; then
    die 1 "[00] Package installation failed; verify apt sources and rerun"
  fi
fi

# Proxmox checks (optional but recommended)
if ! has qm; then
  log_warn "[00] Proxmox 'qm' not found. These scripts expect to run on a Proxmox host."
fi
if ! has pve-firewall; then
  log_warn "[00] Proxmox 'pve-firewall' not found. Node firewall step may be skipped."
fi

log_info "[00] OK."
