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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"

log_info "[00] Validating host environment (Linux + tools)..."

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

:

log_info "[00] OK."
