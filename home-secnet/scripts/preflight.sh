#!/usr/bin/env bash
set -euo pipefail

echo "[00] Validating host environment (Linux + Proxmox + tools)..."

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "[preflight] This project targets Linux (Debian/Ubuntu)." >&2
  exit 1
fi

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[00] Run as root for package installation." >&2
    exit 1
  fi
}

has() { command -v "$1" >/dev/null 2>&1; }

# Detect package manager
PKG=""
if has apt-get; then PKG=apt; else
  echo "[00] Unsupported distro (requires apt)." >&2
  exit 1
fi

req_bins=(curl rsync ssh bash nft wg envsubst perl openssl)
miss=()
for b in "${req_bins[@]}"; do
  if ! has "$b"; then miss+=("$b"); fi
done

if (( ${#miss[@]} )); then
  echo "[00] Missing tools: ${miss[*]}"
  need_root
  echo "[00] Installing required packages..."
  apt-get update -y
  # Map common names to Debian packages
  apt-get install -y curl rsync openssh-client nftables wireguard-tools gettext-base perl openssl || true
fi

# Proxmox checks (optional but recommended)
if ! has qm; then
  echo "[00] Proxmox 'qm' not found. These scripts expect to run on a Proxmox host."
fi
if ! has pve-firewall; then
  echo "[00] Proxmox 'pve-firewall' not found. Node firewall step may be skipped."
fi

echo "[00] OK."
