#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Purpose: Render OpenWRT overlay from templates into home-secnet/render/openwrt/overlay
# Inputs: .env (OpenWRT_*, LAN/WAN, WG_*, SPA_*)
# Outputs: home-secnet/render/openwrt/overlay tree with UCI, nft includes, procd unit, configs
# Side effects: creates/updates .env for missing defaults (no secrets in logs), writes PSK file under overlay

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES_DIR="$ROOT_DIR/openwrt/templates"
RENDER_DIR="$ROOT_DIR/render/openwrt/overlay"
LIB_DIR="$ROOT_DIR/scripts/lib"

# shellcheck disable=SC1090
source "$LIB_DIR/log.sh"
# shellcheck disable=SC1090
source "$LIB_DIR/env.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--force]
Render OpenWRT overlay into render/openwrt/overlay using templates and .env

Environment (from .env):
  OPENWRT_VERSION, OPENWRT_TARGET, OPENWRT_PROFILE
  LAN_IF, WAN_IF (fallback to ROUTER_LAN_IF/ROUTER_WAN_IF)
  NET_TRUSTED, GW_TRUSTED
  WG_PORT, WG_SERVER_IP, WG_SERVER_PRIVKEY (optional)
  SPA_ENABLE=true, SPA_MODE=pqkem, SPA_PQ_PORT, SPA_PQ_OPEN_SECS, SPA_PQ_WINDOW_SECS, SPA_PQ_PSK_B64
  ADGUARD_UI_LISTEN (default 127.0.0.1:3000), DNS_BLOCKLISTS_MIN (default true)
USAGE
}

FORCE=0
if [[ ${1:-} == "--help" ]]; then usage; exit 0; fi
if [[ ${1:-} == "--force" ]]; then FORCE=1; fi

mkdir -p "$RENDER_DIR"

load_env

# Defaults & derived values
export OPENWRT_VERSION="${OPENWRT_VERSION:-23.05.4}"
export OPENWRT_TARGET="${OPENWRT_TARGET:-x86/64}"
export OPENWRT_PROFILE="${OPENWRT_PROFILE:-generic}"

# Interfaces (prefer OpenWRT-specific, fallback to legacy vars)
export LAN_IF="${LAN_IF:-${ROUTER_LAN_IF:-lan0}}"
export WAN_IF="${WAN_IF:-${ROUTER_WAN_IF:-wan0}}"

# Host identity
export ROUTER_HOSTNAME="${ROUTER_HOSTNAME:-winder}"
export TZ="${TZ:-UTC}"

# LAN addressing; derive from existing trusted net if available
cidr_to_netmask() { local i mask=""; local c="${1#*/}"; for ((i=0;i<4;i++)); do local n=$(( (c>8?8:c) )); c=$((c-n)); mask+=$(( 256 - 2**(8-n) )); [[ $i -lt 3 ]] && mask+=.; done; printf '%s' "$mask"; }

NET_TRUSTED="${NET_TRUSTED:-10.20.0.0/24}"
GW_TRUSTED="${GW_TRUSTED:-10.20.0.1}"
export LAN_ADDR="${LAN_ADDR:-$GW_TRUSTED}"
export LAN_NETMASK="${LAN_NETMASK:-$(cidr_to_netmask "$NET_TRUSTED") }"

# WireGuard
export WG_PORT="${WG_PORT:-51820}"
export WG_SERVER_IP="${WG_SERVER_IP:-10.66.66.1/24}"
export WG_SERVER_PRIVKEY="${WG_SERVER_PRIVKEY:-}"
if [[ -z "$WG_SERVER_PRIVKEY" ]]; then
  if command -v wg >/dev/null 2>&1; then
    log_info "Generating WireGuard server key (local)"
    WG_SERVER_PRIVKEY="$(wg genkey)" || die 1 "wg genkey failed"
    export WG_SERVER_PRIVKEY
  else
    log_warn "wg not found; leaving WG_SERVER_PRIVKEY empty (set later on device)"
  fi
fi

# SPA
export SPA_ENABLE="${SPA_ENABLE:-true}"
export SPA_MODE="${SPA_MODE:-pqkem}"
export SPA_PQ_PORT="${SPA_PQ_PORT:-62201}"
export SPA_PQ_OPEN_SECS="${SPA_PQ_OPEN_SECS:-45}"
export SPA_PQ_WINDOW_SECS="${SPA_PQ_WINDOW_SECS:-30}"
export SPA_PQ_PSK_FILE="${SPA_PQ_PSK_FILE:-/etc/spa/psk.bin}"
export SPA_PQ_KEM="${SPA_PQ_KEM:-kyber768}"
export ADGUARD_UI_LISTEN="${ADGUARD_UI_LISTEN:-127.0.0.1:3000}"
export DNS_BLOCKLISTS_MIN="${DNS_BLOCKLISTS_MIN:-true}"

# Ensure PSK exists (do not modify .env here; only setup_env.sh writes .env)
if [[ "${SPA_ENABLE}" == "true" && "${SPA_MODE}" == "pqkem" ]]; then
  if [[ -z "${SPA_PQ_PSK_B64:-}" ]]; then
    log_warn "SPA_PQ_PSK_B64 is empty; generating ephemeral PSK for overlay only. Persist it by adding SPA_PQ_PSK_B64=<base64> to .env"
    SPA_PQ_PSK_B64="$(head -c 32 /dev/urandom | base64)"
  fi
  export SPA_PQ_PSK_B64
fi

render_tpl() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  # shellcheck disable=SC2016
  envsubst < "$src" > "$dest.tmp"
  mv "$dest.tmp" "$dest"
}

log_info "Rendering OpenWRT overlay to $RENDER_DIR"

# nftables include (SPA gate)
render_tpl "$TEMPLATES_DIR/etc/nftables.d/99-wg-spa.nft.tpl" \
  "$RENDER_DIR/etc/nftables.d/99-wg-spa.nft"

# procd init for SPA
render_tpl "$TEMPLATES_DIR/etc/init.d/spa-pq.tpl" \
  "$RENDER_DIR/etc/init.d/spa-pq"
chmod 0755 "$RENDER_DIR/etc/init.d/spa-pq"

# UCI configs
render_tpl "$TEMPLATES_DIR/etc/config/network.tpl" \
  "$RENDER_DIR/etc/config/network"
render_tpl "$TEMPLATES_DIR/etc/config/firewall.tpl" \
  "$RENDER_DIR/etc/config/firewall"
render_tpl "$TEMPLATES_DIR/etc/config/dhcp.tpl" \
  "$RENDER_DIR/etc/config/dhcp"
render_tpl "$TEMPLATES_DIR/etc/config/system.tpl" \
  "$RENDER_DIR/etc/config/system"

# DNS stack files
render_tpl "$TEMPLATES_DIR/etc/adguardhome.yaml.tpl" \
  "$RENDER_DIR/etc/AdGuardHome.yaml"
render_tpl "$TEMPLATES_DIR/etc/unbound/unbound.conf.tpl" \
  "$RENDER_DIR/etc/unbound/unbound.conf"

# First boot enablement and config includes
render_tpl "$TEMPLATES_DIR/etc/uci-defaults/99-winder-defaults.tpl" \
  "$RENDER_DIR/etc/uci-defaults/99-winder-defaults"
chmod 0755 "$RENDER_DIR/etc/uci-defaults/99-winder-defaults"

# Optionally embed SPA binary if staged locally
maybe_embed_spa() {
  local bin_dest="$RENDER_DIR/usr/bin/home-secnet-spa-pq"
  local staged=""
  if [[ -f "$ROOT_DIR/render/opt/spa/home-secnet-spa-pq" ]]; then
    staged="$ROOT_DIR/render/opt/spa/home-secnet-spa-pq"
  else
    staged="$(ls -1 $ROOT_DIR/router/spa-pq/target/*/release/home-secnet-spa-pq 2>/dev/null | head -n1 || true)"
  fi
  if [[ -n "$staged" ]]; then
    mkdir -p "$(dirname "$bin_dest")"
    install -m 0755 "$staged" "$bin_dest"
    log_info "Embedded SPA binary: $(basename "$staged")"
  else
    log_warn "SPA binary not staged; /etc/init.d/spa-pq may fail until binary is provisioned at /usr/bin/home-secnet-spa-pq"
  fi
}

if [[ "${SPA_ENABLE}" == "true" && "${SPA_MODE}" == "pqkem" ]]; then
  maybe_embed_spa
fi

# Secrets: SPA PSK
if [[ "${SPA_ENABLE}" == "true" && "${SPA_MODE}" == "pqkem" ]]; then
  mkdir -p "$RENDER_DIR/etc/spa"
  umask 077
  printf '%s' "$SPA_PQ_PSK_B64" | base64 -d > "$RENDER_DIR$SPA_PQ_PSK_FILE"
  chmod 0600 "$RENDER_DIR$SPA_PQ_PSK_FILE"
  umask 022
fi

log_info "Done. Overlay at $RENDER_DIR"
echo "- nft gate:     etc/nftables.d/99-wg-spa.nft"
echo "- spa service:  etc/init.d/spa-pq"
echo "- uci configs:  etc/config/{network,firewall,dhcp,system}"
echo "- dns:          etc/adguardhome.yaml + etc/unbound/unbound.conf"
echo "- first-boot:   etc/uci-defaults/99-winder-defaults"
