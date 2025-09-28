#!/bin/sh

# Ensure nftables include is wired and services enabled on first boot

# Enable custom chains and include SPA nft file
uci -q set firewall.@defaults[0].custom_chains='1'
INCLUDE_IDX=$(uci -q show firewall | grep -c '^firewall\.@include\[' || true)
if [ "$INCLUDE_IDX" -eq 0 ] || ! uci -q show firewall | grep -q "99-wg-spa.nft"; then
  uci -q add firewall include >/dev/null
  uci -q set firewall.@include[-1].type='nftables'
  uci -q set firewall.@include[-1].path='/etc/nftables.d/99-wg-spa.nft'
fi
uci -q commit firewall

# Enable services if present
[ -x /etc/init.d/spa-pq ] && /etc/init.d/spa-pq enable || true
[ -x /etc/init.d/unbound ] && /etc/init.d/unbound enable || true
[ -x /etc/init.d/AdGuardHome ] && /etc/init.d/AdGuardHome enable || true

# Generate WireGuard server key if missing
if command -v wg >/dev/null 2>&1; then
  PRIVK=$(uci -q get network.wg0.private_key 2>/dev/null)
  if [ -z "$PRIVK" ]; then
    umask 077
    mkdir -p /etc/wireguard
    wg genkey > /etc/wireguard/server.key
    PRIVK=$(cat /etc/wireguard/server.key)
    uci -q set network.wg0.private_key="$PRIVK"
    uci -q commit network
  fi
fi

exit 0

