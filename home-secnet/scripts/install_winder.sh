#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Purpose: Bootstrap Winder v0.1.0 on a Proxmox host
# Inputs: none (interactive setup wizard will prompt)
# Outputs: installs repo under /root/winder and runs setup
# Side effects: installs git/curl/unzip, creates /root/winder, runs make router

usage() {
  cat <<'USAGE'
Usage: install_winder.sh [--ultralight]
  Downloads v0.1.0 (via tarball), runs preflight and setup, then deploys router.

Options:
  --ultralight    After setup, run the ultralight target instead of full router
USAGE
}

TARGET="router"
if [[ "${1:-}" == "--ultralight" ]]; then TARGET="ultralight"; fi

if [[ $EUID -ne 0 ]]; then
  echo "Run as root on Proxmox host" >&2; exit 1
fi

apt-get update -y
apt-get install -y curl unzip

cd /root
if [[ -d /root/winder ]]; then
  echo "Existing /root/winder present. Move or remove it before installing." >&2
  exit 1
fi

curl -fsSL -o winder-v0.1.0.tar.gz https://github.com/csysp/winder/archive/refs/tags/v0.1.0.tar.gz
tar -xzf winder-v0.1.0.tar.gz
mv winder-0.1.0 winder
cd winder

bash home-secnet/scripts/preflight.sh
bash home-secnet/scripts/setup_env.sh

make -C home-secnet "$TARGET"

echo "Install complete. See home-secnet/README.md for next steps."

