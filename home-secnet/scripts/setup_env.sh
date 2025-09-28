#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Interactive helper to create/update .env from .env.example.
# Inputs: VERBOSE (optional)
# Outputs: writes home-secnet/.env
# Side effects: Creates/updates .env (idempotent)

usage() {
  cat <<'USAGE'
Usage: setup_env.sh
  Guides creation of home-secnet/.env from .env.example.

Environment:
  VERBOSE=1   Enable verbose logging
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ENV_ROOT/.env"
ENV_EXAMPLE="$ENV_ROOT/.env.example"

# Helpers
update_env() {
  local key="$1"; shift
  local val="$1"; shift || true
  local tmp
  tmp="${ENV_FILE}.tmp$$"
  umask 077
  if [[ -f "$ENV_FILE" ]]; then
    # replace existing key or append
    if rg -n "^${key}=" "$ENV_FILE" >/dev/null 2>&1; then
      sed -E "s|^(${key}=).*|\\1${val}|" "$ENV_FILE" >"$tmp"
    else
      cat "$ENV_FILE" >"$tmp"
      printf '%s=%s\n' "$key" "$val" >>"$tmp"
    fi
  else
    printf '%s=%s\n' "$key" "$val" >"$tmp"
  fi
  mv -f "$tmp" "$ENV_FILE"
}

ensure_default() {
  local key="$1"; local def="$2"
  # shellcheck disable=SC2154
  if [[ -z "${!key:-}" ]]; then
    export "$key"="$def"
  fi
}

require_nonempty() {
  local key="$1"; shift
  local prompt="$*"
  local val="${!key:-}"
  while [[ -z "$val" ]]; do
    read -r -p "$prompt: " val
  done
  export "$key"="$val"
  update_env "$key" "$val"
}

# Load defaults early (avoid unbound vars)
set +u
# shellcheck disable=SC1090
[[ -f "$ENV_EXAMPLE" ]] && source "$ENV_EXAMPLE"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
set -u

# Provider selection (baremetal default; prefer proxmox if detected, ask to confirm)
detect_proxmox() {
  command -v qm >/dev/null 2>&1 && command -v pve-firewall >/dev/null 2>&1
}

if [[ -z "${HOST_PROVIDER:-}" ]]; then
  if detect_proxmox; then
    read -r -p "Proxmox tools detected. Use Proxmox provider? [Y/n] " _p
    if [[ "${_p:-Y}" =~ ^([Yy]|)$ ]]; then
      HOST_PROVIDER=proxmox
    else
      HOST_PROVIDER=baremetal
    fi
  else
    HOST_PROVIDER=baremetal
  fi
  export HOST_PROVIDER
  update_env HOST_PROVIDER "${HOST_PROVIDER}"
fi

# Apply requested default behaviors in-memory if not set
ensure_default MODE openwrt
ensure_default WRAP_MODE hysteria2
ensure_default DNS_STACK adguard
ensure_default SPA_ENABLE true
ensure_default DOUBLE_HOP_ENABLE true
update_env MODE "${MODE}"

# Randomize WG_PORT once if unset and persist immediately
if [[ -z "${WG_PORT:-}" ]]; then
  WG_PORT=$(( (RANDOM % 41000) + 20000 ))
  export WG_PORT
  update_env WG_PORT "$WG_PORT"
fi

# Early NIC detection when unset
if [[ -z "${PHYS_WAN_IF:-}" || -z "${PHYS_LAN_IF:-}" ]]; then
  echo "[01] Detecting NICs to prefill WAN/LAN..."
  "$SCRIPT_DIR/detect_nics.sh" || true
  # Reload env after detection
  set +u
  # shellcheck disable=SC1090
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
  set -u
fi

echo ""
if [[ "${ULTRALIGHT_EXPERIMENTAL:-0}" == "1" ]]; then
  echo "Ultralight Mode targets old/tiny x86 and Pi-class devices. (EXPERIMENTAL)"
  read -r -p "Enable Ultralight Mode (disable Suricata, use dnsmasq, minimal logs)? [y/N] " _ul
  if [[ "${_ul}" =~ ^[Yy]$ ]]; then
    export ULTRALIGHT_MODE=true
    export IDS_MODE=none
    export DHCP_STACK=dnsmasq
    export DNS_STACK=unbound
    export NFT_GUARD_ENABLE=true
    export NFT_SYNOPROXY_ENABLE=true
    export NFT_RATE_LIMIT_ENABLE=true
    export NFT_BOGONS_ENABLE=true
    export NFT_DYNAMIC_BAN_ENABLE=false
    export SHAPING_ENABLE=true
    export LOG_VERBOSITY=minimal
  else
    export ULTRALIGHT_MODE=false
  fi
else
  export ULTRALIGHT_MODE=false
fi

# Persist choices via upsert
update_env ULTRALIGHT_MODE "${ULTRALIGHT_MODE}"
update_env IDS_MODE "${IDS_MODE:-none}"
update_env DHCP_STACK "${DHCP_STACK:-dnsmasq}"
update_env DNS_STACK "${DNS_STACK:-adguard}"
update_env NFT_GUARD_ENABLE "${NFT_GUARD_ENABLE:-true}"
update_env NFT_SYNOPROXY_ENABLE "${NFT_SYNOPROXY_ENABLE:-true}"
update_env NFT_RATE_LIMIT_ENABLE "${NFT_RATE_LIMIT_ENABLE:-true}"
update_env NFT_BOGONS_ENABLE "${NFT_BOGONS_ENABLE:-true}"
update_env NFT_DYNAMIC_BAN_ENABLE "${NFT_DYNAMIC_BAN_ENABLE:-false}"
update_env SHAPING_ENABLE "${SHAPING_ENABLE:-true}"
update_env LOG_VERBOSITY "${LOG_VERBOSITY:-minimal}"

# Ensure required fields (provider-specific)
if [[ "${HOST_PROVIDER}" == "proxmox" ]]; then
  require_nonempty PVE_NODE "Proxmox node name (e.g., pve)"
fi

# Randomize WG_PORT on first setup if not already set
if ! grep -q '^WG_PORT=' "$(dirname "$0")/../.env" 2>/dev/null; then
  # Choose a UDP port in 20000-61000 range avoiding common services
  WG_PORT=$(( (RANDOM % 41000) + 20000 ))
  printf 'WG_PORT=%s\n' "$WG_PORT" >> "$(dirname "$0")/../.env"
fi

# Run NIC detection on initial setup to prefill physical mappings
if ! grep -q '^PHYS_WAN_IF=' "$(dirname "$0")/../.env" 2>/dev/null; then
  echo "[01] Detecting NICs to prefill WAN/LAN..."
  "$(dirname "$0")/detect_nics.sh" || true
fi

# Set sane defaults for essential features on first run
if ! grep -q '^WRAP_MODE=' "$(dirname "$0")/../.env" 2>/dev/null; then
  echo "WRAP_MODE=hysteria2" >> "$(dirname "$0")/../.env"
fi
if ! grep -q '^DNS_STACK=' "$(dirname "$0")/../.env" 2>/dev/null; then
  echo "DNS_STACK=adguard" >> "$(dirname "$0")/../.env"
fi
if ! grep -q '^SPA_ENABLE=' "$(dirname "$0")/../.env" 2>/dev/null; then
  echo "SPA_ENABLE=true" >> "$(dirname "$0")/../.env"
fi
if ! grep -q '^DOUBLE_HOP_ENABLE=' "$(dirname "$0")/../.env" 2>/dev/null; then
  echo "DOUBLE_HOP_ENABLE=true" >> "$(dirname "$0")/../.env"
fi
# shellcheck source=scripts/lib/log.sh
# shellcheck source=home-secnet/scripts/lib/log.sh
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"
if [[ -f "$LIB_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$LIB_PATH"
fi

log_info "[01] Preparing .env with interactive prompts..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Single Packet Authorization (SPA)
ensure_choice SPA_ENABLE "Enable Single Packet Authorization?" "false" "true,false"
if [[ "$SPA_ENABLE" == "true" ]]; then
  ensure_env SPA_PORT "SPA knock port" "62201" '^[0-9]{2,5}$'
  ensure_env SPA_TIMEOUT "SPA access timeout (seconds)" "30" '^[0-9]+$'
  # Keys are auto-generated during render if not set
  
  # Validate SPA port doesn't conflict with other services
  if [[ "$SPA_PORT" == "$WG_PORT" ]]; then
    echo "[env] WARNING: SPA port ($SPA_PORT) conflicts with WireGuard port. Consider using a different port."
  fi
  if [[ "$SPA_PORT" == "22" || "$SPA_PORT" == "53" || "$SPA_PORT" == "67" || "$SPA_PORT" == "68" ]]; then
    echo "[env] WARNING: SPA port ($SPA_PORT) conflicts with common services. Consider using a different port."
  fi
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

# Double-hop egress (optional)
ensure_choice DOUBLE_HOP_ENABLE "Enable WG double-hop egress?" "false" "true,false"
if [[ "$DOUBLE_HOP_ENABLE" == "true" ]]; then
  ensure_env WG2_ADDRESS "Router wg1 address (CIDR)" "10.67.0.2/32"
  ensure_env WG2_ENDPOINT "Exit endpoint (host:port)" "exit.example.com:51820"
  ensure_env WG2_PEER_PUBLIC_KEY "Exit peer public key" ""
  ensure_env WG2_ALLOWED_IPS "wg1 AllowedIPs" "0.0.0.0/0"
fi

ensure_env DNS_RECURSORS "Upstream DNS forwarders (optional)" "9.9.9.9 1.1.1.1"

# Router Interface Names
ensure_env ROUTER_WAN_IF "Router WAN interface name" "ens18"
ensure_env ROUTER_LAN_IF "Router LAN interface name" "ens19"

# Bridge Names
ensure_env VM_BR_WAN "WAN bridge name" "vmbr0"
ensure_env VM_BR_LAN "LAN bridge name" "vmbr1"

# Security Configuration
ensure_choice DISABLE_USB_STORAGE "Disable USB storage?" "true" "true,false"
ensure_choice HARDEN_AUDITD "Enable auditd hardening?" "true" "true,false"
ensure_choice INSTALL_AIDE "Install AIDE file integrity monitor?" "true" "true,false"
ensure_choice FAIL2BAN_ENABLE "Enable fail2ban?" "true" "true,false"

# Software Versions
ensure_env ADGUARD_VERSION "AdGuard Home version" "latest"

# Proxmox defaults
ensure_env PVE_NODE "Proxmox node name" "$(hostname)"
ensure_env ISO_STORAGE "Proxmox ISO storage" "local"
ensure_env DISK_STORAGE "Proxmox disk storage" "local-lvm"

ensure_env ROUTER_VM_ID "Router VMID" "201" '^[0-9]+$'
ensure_env ROUTER_VM_NAME "Router VM name" "router-vm"
ensure_env ROUTER_CPU "Router CPU cores" "4" '^[0-9]+$'
ensure_env ROUTER_RAM "Router RAM (MB)" "4096" '^[0-9]+$'


# Admin and SSH key
ensure_env ROUTER_ADMIN_USER "Router admin username" "admin"

router_key_default=""
if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then router_key_default=$(cat "$HOME/.ssh/id_ed25519.pub"); fi
ensure_env ROUTER_ADMIN_PUBKEY "Paste Router admin SSH public key" "${router_key_default:-ssh-ed25519 AAAA... yourkey}"


# Alert Email Configuration
ensure_env ALERT_EMAIL "Alert email address (optional)" ""
ensure_choice SMTP_ENABLE "Enable SMTP relay for alerts?" "false" "true,false"
if [[ "$SMTP_ENABLE" == "true" ]]; then
  ensure_env SMTP_HOST "SMTP server hostname" ""
  ensure_env SMTP_PORT "SMTP server port" "587" '^[0-9]+$'
  ensure_env SMTP_USER "SMTP username" ""
  ensure_env SMTP_PASS "SMTP password" ""
  ensure_env SMTP_FROM "SMTP from address" ""
fi

echo "[01] .env updated with provided values."
