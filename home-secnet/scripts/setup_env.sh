#!/usr/bin/env bash
set -euo pipefail

echo "[01] Preparing .env with interactive prompts..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# shellcheck source=./lib/env.sh
source "$ROOT_DIR/scripts/lib/env.sh"

ensure_env_file
load_env

# Core choices
ensure_choice ISP_WAN_TYPE "WAN type" "dhcp" "dhcp,static"
if [[ "$ISP_WAN_TYPE" == "static" ]]; then
  ensure_env WAN_STATIC_IP "Static WAN IP (CIDR or IP)" "198.51.100.2/24"
  ensure_env WAN_STATIC_GW "Static WAN Gateway" "198.51.100.1"
  ensure_env WAN_STATIC_DNS "Upstream DNS (space-separated)" "1.1.1.1 9.9.9.9"
fi

ensure_choice DNS_STACK "DNS stack" "adguard" "unbound,adguard"
ensure_choice USE_VLANS "Use VLAN segmentation?" "false" "true,false"

# WireGuard wrapper / obfuscation
ensure_choice WRAP_MODE "WireGuard wrapper mode" "none" "none,hysteria2"
if [[ "$WRAP_MODE" == "hysteria2" ]]; then
  ensure_env WRAP_LISTEN_PORT "Hysteria2 UDP listen port" "443" '^[0-9]{2,5}$'
  ensure_env WRAP_PASSWORD "Hysteria2 shared password" "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)"
  ensure_env WRAP_DOMAIN "Hysteria2 SNI/Server Name (optional)" ""
fi

# WireGuard basics
default_port=$(random_high_port)
ensure_env WG_PORT "WireGuard UDP port" "$default_port" '^[0-9]{4,5}$'
ensure_env WG_NET "WireGuard subnet" "10.66.66.0/24"
ensure_env WG_SERVER_IP "WireGuard server address (CIDR)" "10.66.66.1/24"
ensure_env WG_ALLOWED_IPS "WG AllowedIPs for clients" "0.0.0.0/0, ::/0"
ensure_env WG_PERSISTENT_KEEPALIVE "WG PersistentKeepalive (seconds)" "25" '^[0-9]+$'
ensure_env WG_DNS "WG DNS address (usually server IP without /mask)" "10.66.66.1"

if [[ "$USE_VLANS" == "true" ]]; then
  # VLANs and subnets
  ensure_env VLAN_TRUSTED "VLAN ID for TRUSTED" "20" '^[0-9]+$'
  ensure_env VLAN_IOT "VLAN ID for IOT" "30" '^[0-9]+$'
  ensure_env VLAN_GUEST "VLAN ID for GUEST" "40" '^[0-9]+$'
  ensure_env VLAN_LAB "VLAN ID for LAB" "50" '^[0-9]+$'

  ensure_env NET_TRUSTED "Subnet TRUSTED" "10.20.0.0/24"
  ensure_env NET_IOT "Subnet IOT" "10.30.0.0/24"
  ensure_env NET_GUEST "Subnet GUEST" "10.40.0.0/24"
  ensure_env NET_LAB "Subnet LAB" "10.50.0.0/24"

  ensure_env GW_TRUSTED "Gateway TRUSTED" "10.20.0.1"
  ensure_env GW_IOT "Gateway IOT" "10.30.0.1"
  ensure_env GW_GUEST "Gateway GUEST" "10.40.0.1"
  ensure_env GW_LAB "Gateway LAB" "10.50.0.1"

  ensure_env DHCP_TRUSTED_RANGE "DHCP range TRUSTED" "10.20.0.100 10.20.0.200"
  ensure_env DHCP_IOT_RANGE "DHCP range IOT" "10.30.0.100 10.30.0.200"
  ensure_env DHCP_GUEST_RANGE "DHCP range GUEST" "10.40.0.100 10.40.0.200"
  ensure_env DHCP_LAB_RANGE "DHCP range LAB" "10.50.0.100 10.50.0.200"
else
  # Flat LAN only
  ensure_env NET_TRUSTED "LAN subnet" "10.20.0.0/24"
  ensure_env GW_TRUSTED "LAN gateway IP" "10.20.0.1"
  ensure_env DHCP_TRUSTED_RANGE "LAN DHCP range" "10.20.0.100 10.20.0.200"
fi

# Double-hop egress
ensure_choice DOUBLE_HOP_ENABLE "Enable WG double-hop egress?" "false" "true,false"
if [[ "$DOUBLE_HOP_ENABLE" == "true" ]]; then
  ensure_env WG2_ADDRESS "Router wg1 address (CIDR)" "10.67.0.2/32"
  ensure_env WG2_ENDPOINT "Exit endpoint (host:port)" "exit.example.com:51820"
  ensure_env WG2_PEER_PUBLIC_KEY "Exit peer public key" ""
  ensure_env WG2_ALLOWED_IPS "wg1 AllowedIPs" "0.0.0.0/0"
fi

ensure_env DNS_RECURSORS "Upstream DNS forwarders (optional)" "9.9.9.9 1.1.1.1"

# Proxmox defaults
ensure_env PVE_NODE "Proxmox node name" "$(hostname)"
ensure_env ISO_STORAGE "Proxmox ISO storage" "local"
ensure_env DISK_STORAGE "Proxmox disk storage" "local-lvm"

ensure_env ROUTER_VM_ID "Router VMID" "201" '^[0-9]+$'
ensure_env ROUTER_VM_NAME "Router VM name" "router-vm"
ensure_env ROUTER_CPU "Router CPU cores" "4" '^[0-9]+$'
ensure_env ROUTER_RAM "Router RAM (MB)" "4096" '^[0-9]+$'

ensure_env LOG_VM_ID "Logging VMID" "202" '^[0-9]+$'
ensure_env LOG_VM_NAME "Logging VM name" "log-vm"
ensure_env LOG_CPU "Logging CPU cores" "2" '^[0-9]+$'
ensure_env LOG_RAM "Logging RAM (MB)" "2048" '^[0-9]+$'

# Admins and SSH keys
ensure_env ROUTER_ADMIN_USER "Router admin username" "admin"
ensure_env LOG_ADMIN_USER "Logging admin username" "admin"

router_key_default=""
if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then router_key_default=$(cat "$HOME/.ssh/id_ed25519.pub"); fi
ensure_env ROUTER_ADMIN_PUBKEY "Paste Router admin SSH public key" "${router_key_default:-ssh-ed25519 AAAA... yourkey}"

log_key_default=""
if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then log_key_default=$(cat "$HOME/.ssh/id_ed25519.pub"); fi
ensure_env LOG_ADMIN_PUBKEY "Paste Logging admin SSH public key" "${log_key_default:-ssh-ed25519 AAAA... yourkey}"

echo "[01] .env updated with provided values."
