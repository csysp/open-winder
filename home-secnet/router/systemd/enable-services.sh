#!/usr/bin/env bash
set -euo pipefail

echo "Enabling core services on Router VM..."
sudo systemctl enable --now nftables
sudo systemctl enable --now isc-dhcp-server
if [[ -f /etc/unbound/unbound.conf ]]; then
  sudo systemctl enable --now unbound
fi
if [[ -f /etc/wireguard/wg0.conf ]]; then
  sudo systemctl enable --now wg-quick@wg0
fi
sudo systemctl enable --now suricata || true
sudo sysctl -w net.ipv4.ip_forward=1
echo "Done."

