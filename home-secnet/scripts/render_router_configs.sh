#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Render router configuration files into home-secnet/render/.
# Inputs: .env via scripts/lib/env.sh; VERBOSE (optional)
# Outputs: files under home-secnet/render/
# Side effects: Writes render artifacts.

usage() {
  cat <<'USAGE'
Usage: render_router_configs.sh
  Renders router configs/templates into home-secnet/render/.

Environment:
  VERBOSE=1   Enable verbose logging
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Derive project root as parent of scripts/ reliably
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# Load environment via common helper (loads .env.example then .env)
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/env.sh" ]] && source "${SCRIPT_DIR}/lib/env.sh"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# Fallback logger for CI if log.sh was not sourced for any reason
if ! declare -f log_info >/dev/null 2>&1; then
  log_info() { echo "$*"; }
  log_warn() { echo "$*" >&2; }
fi
# Ensure render roots exist as early as possible (CI-safe)
mkdir -p "$ROOT_DIR/render" \
"$ROOT_DIR/render/openwrt/etc/config" \
"$ROOT_DIR/render/openwrt/etc/nftables.d" \
"$ROOT_DIR/render/openwrt/etc/init.d" \
"$ROOT_DIR/render/openwrt/etc/uci-defaults" \
"$ROOT_DIR/render/openwrt/etc/hysteria" || true
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# Ensure OpenWRT overlay base directories always exist (CI-safe)
export -p >/dev/null 2>&1 || true
mkdir -p "$ROOT_DIR/render/openwrt/etc/config" \
"$ROOT_DIR/render/openwrt/etc/nftables.d" \
"$ROOT_DIR/render/openwrt/etc/init.d" \
"$ROOT_DIR/render/openwrt/etc/uci-defaults" \
"$ROOT_DIR/render/openwrt/etc/hysteria" || true

log_info "[08] Rendering router configs from .env and generating keys..."

mkdir -p "$ROOT_DIR/render/router/configs" "$ROOT_DIR/clients"

# Generate WireGuard server keys if absent (graceful fallback when wg is unavailable)
WG_DIR="$ROOT_DIR/render/wg"
mkdir -p "$WG_DIR"
if [[ ! -f "$WG_DIR/privatekey" ]]; then
  umask 077
  if command -v wg >/dev/null 2>&1; then
    echo "[08] Generating WireGuard keypair..."
    wg genkey | tee "$WG_DIR/privatekey" | wg pubkey > "$WG_DIR/publickey"
  else
    echo "[08] 'wg' not found; writing placeholder WireGuard keys for render" >&2
    printf '%s\n' "PLACEHOLDER_PRIVATE_KEY" > "$WG_DIR/privatekey"
    printf '%s\n' "PLACEHOLDER_PUBLIC_KEY" > "$WG_DIR/publickey"
  fi
fi
WG_PRIVATE_KEY=$(cat "$WG_DIR/privatekey")
WG_PUBLIC_KEY=$(cat "$WG_DIR/publickey")
export WG_PRIVATE_KEY WG_PUBLIC_KEY

# Helpers for CIDR handling
prefix_len() { echo "$1" | awk -F'/' '{print $2}'; }
net_addr() { echo "$1" | awk -F'/' '{print $1}'; }
mask_from_prefix() {
  local p="$1"; local m=(); local i
  for ((i=0; i<4; i++)); do
    local bits=$(( p>=8 ? 8 : (p>0 ? p : 0) ))
    m+=( $(( 256 - 2**(8-bits) )) )
    p=$(( p-bits ))
  done
  printf "%d.%d.%d.%d\n" "${m[@]}"
}

# Map env vars for OpenWRT templates if needed
export LAN_IF="${LAN_IF:-${ROUTER_LAN_IF:-br-lan}}"
export WAN_IF="${WAN_IF:-${ROUTER_WAN_IF:-wan}}"

# Render OpenWRT overlay templates (envsubst/perl)
render_template() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  umask 077
  if command -v envsubst >/dev/null 2>&1; then
    envsubst < "$src" > "$dst"
  else
    perl -M5.010 -pe 's/\$\{([A-Z0-9_]+)\}/defined $ENV{$1} ? $ENV{$1} : ""/ge' "$src" > "$dst"
  fi
}

# Render OpenWRT overlay templates into render/openwrt when templates exist
if [ -d "$ROOT_DIR/openwrt/templates" ]; then
  echo "[08] Detected OpenWRT templates. Rendering overlay to $ROOT_DIR/render/openwrt ..."
  render_template "$ROOT_DIR/openwrt/templates/etc/config/system.template" "$ROOT_DIR/render/openwrt/etc/config/system" || true
  render_template "$ROOT_DIR/openwrt/templates/etc/config/dhcp.template" "$ROOT_DIR/render/openwrt/etc/config/dhcp" || true
  render_template "$ROOT_DIR/openwrt/templates/etc/config/network.template" "$ROOT_DIR/render/openwrt/etc/config/network" || true
  render_template "$ROOT_DIR/openwrt/templates/etc/config/firewall.template" "$ROOT_DIR/render/openwrt/etc/config/firewall" || true
  render_template "$ROOT_DIR/openwrt/templates/etc/adguardhome.yaml.template" "$ROOT_DIR/render/openwrt/etc/adguardhome.yaml" || true
  render_template "$ROOT_DIR/openwrt/templates/etc/unbound/unbound.conf.template" "$ROOT_DIR/render/openwrt/etc/unbound/unbound.conf" || true
  render_template "$ROOT_DIR/openwrt/templates/etc/nftables.d/99-wg-spa.nft.template" "$ROOT_DIR/render/openwrt/etc/nftables.d/99-wg-spa.nft" || true
  # SPA-PQ init script
  render_template "$ROOT_DIR/openwrt/templates/etc/init.d/spa-pq.template" "$ROOT_DIR/render/openwrt/etc/init.d/spa-pq" || true
  chmod 0755 "$ROOT_DIR/render/openwrt/etc/init.d/spa-pq" || true
  # Hysteria2 wrapper (optional)
  if [[ "${WRAP_MODE:-none}" == "hysteria2" ]]; then
    render_template "$ROOT_DIR/openwrt/templates/etc/hysteria/config.yaml.template" "$ROOT_DIR/render/openwrt/etc/hysteria/config.yaml" || true
    render_template "$ROOT_DIR/openwrt/templates/etc/init.d/hysteria.template" "$ROOT_DIR/render/openwrt/etc/init.d/hysteria" || true
    chmod 0755 "$ROOT_DIR/render/openwrt/etc/init.d/hysteria" || true
    render_template "$ROOT_DIR/openwrt/templates/etc/uci-defaults/99-hysteria-enable.template" "$ROOT_DIR/render/openwrt/etc/uci-defaults/99-hysteria-enable" || true
    chmod 0755 "$ROOT_DIR/render/openwrt/etc/uci-defaults/99-hysteria-enable" || true
    render_template "$ROOT_DIR/openwrt/templates/etc/nftables.d/20-hysteria.nft.template" "$ROOT_DIR/render/openwrt/etc/nftables.d/20-hysteria.nft" || true
    # Pre-staged binary embedding: copy from render/opt/hysteria if present
    if [[ -f "$ROOT_DIR/render/opt/hysteria/hysteria" ]]; then
      mkdir -p "$ROOT_DIR/render/openwrt/usr/bin"
      cp -f "$ROOT_DIR/render/opt/hysteria/hysteria" "$ROOT_DIR/render/openwrt/usr/bin/hysteria"
      chmod 0755 "$ROOT_DIR/render/openwrt/usr/bin/hysteria"
    fi
  fi
  # Suricata (optional)
  if [[ "${SURICATA_ENABLE:-false}" == "true" ]]; then
    render_template "$ROOT_DIR/openwrt/templates/etc/suricata/suricata.yaml.template" "$ROOT_DIR/render/openwrt/etc/suricata/suricata.yaml" || true
    render_template "$ROOT_DIR/openwrt/templates/etc/init.d/suricata.template" "$ROOT_DIR/render/openwrt/etc/init.d/suricata" || true
    chmod 0755 "$ROOT_DIR/render/openwrt/etc/init.d/suricata" || true
    render_template "$ROOT_DIR/openwrt/templates/etc/uci-defaults/99-suricata-enable.template" "$ROOT_DIR/render/openwrt/etc/uci-defaults/99-suricata-enable" || true
    chmod 0755 "$ROOT_DIR/render/openwrt/etc/uci-defaults/99-suricata-enable" || true
  fi
  # SQM (optional; prefer SQM over custom tc)
  if [[ "${SHAPING_ENABLE:-false}" == "true" ]]; then
    render_template "$ROOT_DIR/openwrt/templates/etc/config/sqm.template" "$ROOT_DIR/render/openwrt/etc/config/sqm" || true
  fi
  # WireGuard egress client (wg1) optional
  if [[ "${WG2_ENABLE:-false}" == "true" ]]; then
    # Append wg1 interface to existing network config
    tmp_net="$ROOT_DIR/render/openwrt/etc/config/network"
    mkdir -p "$(dirname "$tmp_net")"
    frag="$ROOT_DIR/render/meta/network.wg1.fragment"
    render_template "$ROOT_DIR/openwrt/templates/etc/config/network.wg1.template" "$frag" || true
    if [[ -f "$tmp_net" ]]; then
      cat "$frag" >> "$tmp_net"
    else
      cp -f "$frag" "$tmp_net"
    fi
    rm -f "$frag"
  fi
  # MWAN3 (optional)
  if [[ "${MWAN3_ENABLE:-false}" == "true" ]]; then
    render_template "$ROOT_DIR/openwrt/templates/etc/config/mwan3.template" "$ROOT_DIR/render/openwrt/etc/config/mwan3" || true
  fi
  echo "[08] OpenWRT overlay rendered to $ROOT_DIR/render/openwrt/."
fi

# OpenWRT-only branch: stop here to avoid legacy VM/Ubuntu render paths
mkdir -p "$ROOT_DIR/render/openwrt/overlay"
cp -a "$ROOT_DIR/render/openwrt/etc" "$ROOT_DIR/render/openwrt/overlay/" 2>/dev/null || true
exit 0
# Avoid sourcing .env directly elsewhere; lib/env.sh already loaded
# Write env-vars for templates (to render/, not router/)
mkdir -p "$ROOT_DIR/render/meta"
umask 077
cat > "$ROOT_DIR/render/meta/env-vars.sh" <<'EOF'
# Autogenerated by render_router_configs.sh
export ISP_WAN_TYPE=${ISP_WAN_TYPE:-}
export WAN_STATIC_IP=${WAN_STATIC_IP:-}
export WAN_STATIC_GW=${WAN_STATIC_GW:-}
export WAN_STATIC_DNS="${WAN_STATIC_DNS:-}"
export WG_PORT=${WG_PORT:-51820}
export WG_NET=${WG_NET:-}
export WG_SERVER_IP=${WG_SERVER_IP:-}
export WG_ALLOWED_IPS="${WG_ALLOWED_IPS:-}"
export WG_PERSISTENT_KEEPALIVE=${WG_PERSISTENT_KEEPALIVE:-25}
export WG_DNS=${WG_DNS:-}
# VLAN variables (only export if USE_VLANS=true)
if [[ "${USE_VLANS:-false}" == "true" ]]; then
  export VLAN_TRUSTED=${VLAN_TRUSTED:-}
  export VLAN_IOT=${VLAN_IOT:-}
  export VLAN_GUEST=${VLAN_GUEST:-}
  export VLAN_LAB=${VLAN_LAB:-}
  export NET_IOT=${NET_IOT}
  export NET_GUEST=${NET_GUEST}
  export NET_LAB=${NET_LAB}
  export GW_IOT=${GW_IOT}
  export GW_GUEST=${GW_GUEST}
  export GW_LAB=${GW_LAB}
  export DHCP_IOT_RANGE="${DHCP_IOT_RANGE}"
  export DHCP_GUEST_RANGE="${DHCP_GUEST_RANGE}"
  export DHCP_LAB_RANGE="${DHCP_LAB_RANGE}"
fi
# Common variables (always exported)
export NET_TRUSTED=${NET_TRUSTED:-}
export GW_TRUSTED=${GW_TRUSTED:-}
export DHCP_TRUSTED_RANGE="${DHCP_TRUSTED_RANGE:-}"
export DNS_RECURSORS="${DNS_RECURSORS:-}"
export ROUTER_WAN_IF=${ROUTER_WAN_IF:-}
export ROUTER_LAN_IF=${ROUTER_LAN_IF:-}
export DNS_STACK=${DNS_STACK:-adguard}
export WG_PRIVATE_KEY=${WG_PRIVATE_KEY}
export WG_PUBLIC_KEY=${WG_PUBLIC_KEY}
EOF

render() {
  local src="$1" dst="$2"
  set +e
  if command -v envsubst >/dev/null 2>&1; then
    envsubst < "$src" > "$dst"
  else
    # Fallback with perl env substitution for ${VAR}
    perl -M5.010 -pe 's/\$\{([A-Z0-9_]+)\}/defined $ENV{$1} ? $ENV{$1} : ""/ge' "$src" > "$dst"
  fi
  set -e
}

if [[ "${USE_VLANS:-false}" == "true" ]]; then
  # Choose nftables template (SPA vs default)
  if [[ "${SPA_ENABLE:-false}" == "true" ]]; then
    render "$ROOT_DIR/router/configs/nftables.spa.conf" "$ROOT_DIR/render/router/configs/nftables.conf"
  else
    render "$ROOT_DIR/router/configs/nftables.conf" "$ROOT_DIR/render/router/configs/nftables.conf"
  fi
  for f in wg0.conf suricata.yaml tc-shaping.sh; do
    render "$ROOT_DIR/router/configs/$f" "$ROOT_DIR/render/router/configs/$f"
  done
  # Generate DHCP for VLANs with derived masks
  T_PREF=$(prefix_len "$NET_TRUSTED"); T_MASK=$(mask_from_prefix "$T_PREF"); T_NET=$(net_addr "$NET_TRUSTED")
  I_PREF=$(prefix_len "$NET_IOT");     I_MASK=$(mask_from_prefix "$I_PREF"); I_NET=$(net_addr "$NET_IOT")
  G_PREF=$(prefix_len "$NET_GUEST");   G_MASK=$(mask_from_prefix "$G_PREF"); G_NET=$(net_addr "$NET_GUEST")
  L_PREF=$(prefix_len "$NET_LAB");     L_MASK=$(mask_from_prefix "$L_PREF"); L_NET=$(net_addr "$NET_LAB")
  cat > "$ROOT_DIR/render/router/configs/dhcpd.conf" <<EOF
# ISC DHCP (VLANs)
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet ${T_NET} netmask ${T_MASK} {
  option routers ${GW_TRUSTED};
  option domain-name-servers ${GW_TRUSTED};
  range ${DHCP_TRUSTED_RANGE};
}

subnet ${I_NET} netmask ${I_MASK} {
  option routers ${GW_IOT};
  option domain-name-servers ${GW_IOT};
  range ${DHCP_IOT_RANGE};
}

subnet ${G_NET} netmask ${G_MASK} {
  option routers ${GW_GUEST};
  option domain-name-servers ${GW_GUEST};
  range ${DHCP_GUEST_RANGE};
}

subnet ${L_NET} netmask ${L_MASK} {
  option routers ${GW_LAB};
  option domain-name-servers ${GW_LAB};
  range ${DHCP_LAB_RANGE};
}
EOF
  if [[ "${DNS_STACK}" == "unbound" ]]; then
    render "$ROOT_DIR/router/configs/unbound.conf" "$ROOT_DIR/render/router/configs/unbound.conf"
  else
    render "$ROOT_DIR/router/configs/adguard-home.yaml" "$ROOT_DIR/render/router/configs/adguard-home.yaml"
  fi
fi

# Optional: QUIC wrapper (Hysteria2)
if [[ "${WRAP_MODE:-none}" == "hysteria2" ]]; then
  render "$ROOT_DIR/router/configs/hysteria2-server.yaml" "$ROOT_DIR/render/router/configs/hysteria2.yaml"
  # Client sample (run on the client device)
  cat > "$ROOT_DIR/clients/hysteria2-client.yaml" <<EOF
server: ${WRAP_DOMAIN:-<server_ip>}:${WRAP_LISTEN_PORT}
obfs:
  type: salamander
  salamander:
    password: ${WRAP_PASSWORD}
auth: ${WRAP_PASSWORD}
tls:
  sni: ${WRAP_DOMAIN}
  insecure: true
quic:
  init_streams: 64
  max_idle_timeout: 90s
EOF
  echo "[08] QUIC wrapper enabled. Use hysteria2 client to wrap WG UDP over QUIC."
fi

# SPA configs
# SPA configs
if [[ "${SPA_ENABLE:-false}" == "true" ]]; then
  if [[ "${SPA_MODE:-pqkem}" == "pqkem" ]]; then
    echo "[08] SPA mode: PQ-KEM (Kyber + HMAC)"
    SPAQ_DIR="$ROOT_DIR/render/spa/pq"
    mkdir -p "$SPAQ_DIR" "$ROOT_DIR/render/router/systemd"
    # Generate PSK if missing
    if [[ ! -f "$SPAQ_DIR/psk.bin" ]]; then
      umask 077
      head -c 32 /dev/urandom > "$SPAQ_DIR/psk.bin"
    fi
    # Generate Kyber keypair using local built tool if available
    SPA_BIN="$ROOT_DIR/router/spa-pq/target/release/home-secnet-spa-pq"
    if [[ -x "$SPA_BIN" ]]; then
      if [[ ! -f "$SPAQ_DIR/kem_priv.bin" || ! -f "$SPAQ_DIR/kem_pub.bin" ]]; then
        "$SPA_BIN" gen-keys --priv-out "$SPAQ_DIR/kem_priv.bin" --pub-out "$SPAQ_DIR/kem_pub.bin"
      fi
    else
      echo "[08] WARNING: spa-pq binary not found at $SPA_BIN. Run 'make spa' to build locally. Deferring keypair generation to apply step."
    fi
    # Prepare client JSON
    PSK_B64=$(base64 -w0 < "$SPAQ_DIR/psk.bin" 2>/dev/null || base64 < "$SPAQ_DIR/psk.bin")
    if [[ -f "$SPAQ_DIR/kem_pub.bin" ]]; then
      PUB_B64=$(base64 -w0 < "$SPAQ_DIR/kem_pub.bin" 2>/dev/null || base64 < "$SPAQ_DIR/kem_pub.bin")
    else
      PUB_B64="TO_BE_FILLED_AFTER_DEPLOY"
    fi
    cat > "$ROOT_DIR/clients/spa-pq-client.json" <<EOF
{
  "router_host": "<YOUR_PUB_IP>",
  "spa_port": ${SPA_PQ_PORT:-62201},
  "wg_port": ${WG_PORT},
  "kem_pub_b64": "${PUB_B64}",
  "psk_b64": "${PSK_B64}"
}
EOF
    # Render systemd unit with ExecStart args
    cat > "$ROOT_DIR/render/router/systemd/spa-pq.service" <<EOF
[Unit]
Description=Home-SecNet PQ-KEM SPA Daemon
After=network-online.target nftables.service
Wants=network-online.target nftables.service

[Service]
ExecStart=/usr/local/bin/home-secnet-spa-pq run \
  --listen 0.0.0.0:${SPA_PQ_PORT:-62201} \
  --wg-port ${WG_PORT} \
  --kem-priv /etc/spa/kem_priv.bin \
  --psk-file ${SPA_PQ_PSK_FILE:-/etc/spa/psk.bin} \
  --open-secs ${SPA_PQ_OPEN_SECS:-45} \
  --window-secs ${SPA_PQ_WINDOW_SECS:-30} \
  --nft-table inet \
  --nft-chain wg_spa_allow
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF
    echo "[08] PQ-KEM SPA artifacts prepared under render/spa/pq and render/router/systemd/."
  else
    echo "[08] Legacy fwknop mode is no longer supported. Set SPA_MODE=pqkem."
    exit 1
  fi
fi

# Optional: double-hop wg1 to exit node
if [[ "${DOUBLE_HOP_ENABLE:-false}" == "true" ]]; then
  WG2_DIR="$ROOT_DIR/render/wg2"
  mkdir -p "$WG2_DIR"
  if [[ -z "${WG2_PRIVATE_KEY:-}" ]]; then
    echo "[06] Generating wg1 private key..."
    umask 077
    wg genkey > "$WG2_DIR/privatekey"
    WG2_PRIVATE_KEY=$(cat "$WG2_DIR/privatekey")
    # Persist into .env for future renders
    awk -v k="WG2_PRIVATE_KEY" -v v="$WG2_PRIVATE_KEY" 'BEGIN{FS=OFS="="} $1==k {$0=k"="v} {print}' "$ROOT_DIR/.env" > "$ROOT_DIR/.env.tmp" && mv "$ROOT_DIR/.env.tmp" "$ROOT_DIR/.env"
  fi
  export WG2_PRIVATE_KEY
  render "$ROOT_DIR/router/configs/wg1.conf.template" "$ROOT_DIR/render/router/configs/wg1.conf"
  echo "[08] Double-hop enabled. Remember to configure the exit node peer to accept ${WG2_ADDRESS}."
fi

# Enforce QUIC-only if requested: remove any WG UDP allow line from nftables
if [[ "${WRAP_ENFORCE:-false}" == "true" ]]; then
  nftf="$ROOT_DIR/render/router/configs/nftables.conf"
  if [[ -f "$nftf" ]]; then
    # Remove only direct WG accept rules, not SPA-gated ones
    sed -i -E "/udp dport ${WG_PORT}[^@]*$/d" "$nftf"
  fi
fi

# Generate netplan based on ISP_WAN_TYPE
NP_OUT="$ROOT_DIR/render/router/configs/netplan.yaml"
cat > "$NP_OUT" <<EOF
# Generated by render_router_configs.sh
network:
  version: 2
  renderer: networkd
  ethernets:
    ${ROUTER_WAN_IF}:
      optional: true
$(if [[ "$ISP_WAN_TYPE" == "static" ]]; then cat <<EOS
      dhcp4: false
      addresses: [${WAN_STATIC_IP}]
      routes:
        - to: 0.0.0.0/0
          via: ${WAN_STATIC_GW}
      nameservers:
        addresses: [${WAN_STATIC_DNS}]
EOS
else
  cat <<EOS
      dhcp4: true
EOS
fi)
    ${ROUTER_LAN_IF}:
      dhcp4: false
      accept-ra: false
$(if [[ "${USE_VLANS:-false}" == "true" ]]; then cat <<EOS
  vlans:
    ${ROUTER_LAN_IF}.${VLAN_TRUSTED}:
      id: ${VLAN_TRUSTED}
      link: ${ROUTER_LAN_IF}
      addresses: [${GW_TRUSTED}/$(prefix_len "$NET_TRUSTED")]
    ${ROUTER_LAN_IF}.${VLAN_IOT}:
      id: ${VLAN_IOT}
      link: ${ROUTER_LAN_IF}
      addresses: [${GW_IOT}/$(prefix_len "$NET_IOT")]
    ${ROUTER_LAN_IF}.${VLAN_GUEST}:
      id: ${VLAN_GUEST}
      link: ${ROUTER_LAN_IF}
      addresses: [${GW_GUEST}/$(prefix_len "$NET_GUEST")]
    ${ROUTER_LAN_IF}.${VLAN_LAB}:
      id: ${VLAN_LAB}
      link: ${ROUTER_LAN_IF}
      addresses: [${GW_LAB}/$(prefix_len "$NET_LAB")]
EOS
else
  cat <<EOS
      addresses: [${GW_TRUSTED}/$(prefix_len "$NET_TRUSTED")]
EOS
fi)
EOF

# Sample client
CLIENT_PRIV=$(wg genkey)
cat > "$ROOT_DIR/clients/wg-client1.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = 10.66.66.2/24
DNS = ${WG_DNS}

[Peer]
PublicKey = ${WG_PUBLIC_KEY}
AllowedIPs = ${WG_ALLOWED_IPS}
Endpoint = <YOUR_PUB_IP>:${WG_PORT}
PersistentKeepalive = ${WG_PERSISTENT_KEEPALIVE}
EOF

# Local secure logging configuration
cat > "$ROOT_DIR/render/router/configs/rsyslog-secure.conf" <<EOF
# Secure local logging configuration
# Create secure log directory
\$CreateDirs on
\$DirCreateMode 0750
\$FileCreateMode 0640

# Log all system logs to secure directory
*.* /var/log/secure/system.log

# Log authentication events
auth,authpriv.* /var/log/secure/auth.log

# Log kernel messages
kern.* /var/log/secure/kernel.log

# Log mail events
mail.* /var/log/secure/mail.log

# Log cron events
cron.* /var/log/secure/cron.log

# Log daemon events
daemon.* /var/log/secure/daemon.log

# Log local events
local0.* /var/log/secure/local.log
local1.* /var/log/secure/local.log
local2.* /var/log/secure/local.log
local3.* /var/log/secure/local.log
local4.* /var/log/secure/local.log
local5.* /var/log/secure/local.log
local6.* /var/log/secure/local.log
local7.* /var/log/secure/local.log
EOF

echo "[08] Render complete. Artifacts under render/ and clients/."
