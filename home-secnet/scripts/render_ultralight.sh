#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Experimental "ultralight" renderer parked out of main flow.
# Inputs: optional .env in repository root; env flags like DHCP_STACK, DNS_STACK, SHAPING_ENABLE.
# Outputs: files under home-secnet/render/ (ignored by git).
# Notes: Not wired into CI or Make. For local experiments only.

usage() {
  cat <<'USAGE'
Usage: render_ultralight.sh
  Renders an experimental ultralight config set into home-secnet/render/.

Notes:
  - Not wired into CI. OpenWRT overlay is the first-class path.
  - Idempotent and safe to re-run; writes under render/ only.
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ultralight adjustments
if [[ "${ULTRALIGHT_MODE:-false}" == "true" ]]; then
  export IDS_MODE=none
fi

mkdir -p "$(dirname "$0")/../render" "$(dirname "$0")/../render/etc" "$(dirname "$0")/../render/usr/local/sbin" "$(dirname "$0")/../render/etc/systemd/system"
OUT_ROOT="$(cd "$(dirname "$0")/../render" && pwd)"

if [[ "${ULTRALIGHT_MODE:-false}" != "true" && "${ULTRALIGHT_EXPERIMENTAL:-0}" != "1" ]]; then
  echo "[render] Ultralight disabled (future addition)"
fi

# Derive interface names from .env if present
ROUTER_WAN_IF_DEFAULT="wan0"
ROUTER_LAN_IF_DEFAULT="lan0"
if [[ -f "${SCRIPT_DIR}/lib/env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/env.sh"
  set -a; load_env; set +a
fi
WAN_IF_NAME="${ROUTER_WAN_IF:-$ROUTER_WAN_IF_DEFAULT}"
LAN_IF_NAME="${ROUTER_LAN_IF:-$ROUTER_LAN_IF_DEFAULT}"

# DHCP/DNS selection
if [[ "${DHCP_STACK:-dnsmasq}" == "dnsmasq" ]]; then
  mkdir -p "$OUT_ROOT/etc/dnsmasq.d"
  cat > "$OUT_ROOT/etc/dnsmasq.d/home-secnet.conf" <<'EOF'
# dnsmasq: DHCP only (DNS disabled if Unbound is used)
port=0
domain-needed
bogus-priv
expand-hosts
dhcp-authoritative
# Example VLAN scopes (template):
#dhcp-range=lan0,10.10.10.100,10.10.10.200,255.255.255.0,12h
#dhcp-option=lan0,option:router,10.10.10.1
#dhcp-option=lan0,option:dns-server,10.10.10.1
EOF
fi

if [[ "${DNS_STACK:-adguard}" == "unbound" ]]; then
  mkdir -p "$OUT_ROOT/etc/unbound"
  cat > "$OUT_ROOT/etc/unbound/unbound.conf" <<'EOF'
server:
  verbosity: 0
  interface: 0.0.0.0
  do-ip6: no
  cache-min-ttl: 60
  cache-max-ttl: 86400
  prefetch: yes
  qname-minimisation: yes
  harden-referral-path: yes
  harden-algo-downgrade: yes
  hide-identity: yes
  hide-version: yes
  rrset-roundrobin: yes
  unwanted-reply-threshold: 10000000
  val-permissive-mode: no
  auto-trust-anchor-file: "/var/lib/unbound/root.key"
  tls-cert-bundle: "/etc/ssl/certs/ca-certificates.crt"
  # upstreams (edit to taste)
  forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853
    forward-addr: 1.0.0.1@853
EOF
fi

# nftables (ultralight)
if [[ "${NFT_GUARD_ENABLE:-true}" == "true" ]]; then
  mkdir -p "$OUT_ROOT/etc/nftables.d"
  cat > "$OUT_ROOT/etc/nftables.d/ultralight.nft" <<EOF
define WAN = "${WAN_IF_NAME}"
define LAN = "${LAN_IF_NAME}"
define WGPORT = 51820

table inet winder_ultralight {
  sets {
    bogons_v4 { type ipv4_addr; flags interval; auto-merge; }
    naughty_v4 { type ipv4_addr; timeout 10m; }
  }

  chain input_ul {
    type filter hook input priority 10; policy accept;

    iif lo accept
    ct state established,related accept

    # SPA-controlled WG open window
    udp dport $WGPORT jump wg_spa_allow

    # SSH only over WG
    iifname "wg0" tcp dport 22 accept

    # DNS from LAN/WG
    iifname { "$LAN", "wg0" } udp dport 53 accept
    iifname { "$LAN", "wg0" } tcp dport 53 accept

    # Drop bogons on WAN
    iifname "$WAN" ip saddr @bogons_v4 drop

    # Basic ICMP throttling
    ip protocol icmp limit rate over 10/second burst 20 packets drop
    ip6 nexthdr ipv6-icmp limit rate over 10/second burst 20 packets drop

    # Dynamic shun (optional)
    ip saddr @naughty_v4 drop
  }

  chain wg_spa_allow {
    # populated dynamically by SPA daemon
  }

  chain forward_ul {
    type filter hook forward priority 10; policy accept;
    ct state established,related accept

    # LAN -> WAN allowed
    iifname "$LAN" oifname "$WAN" accept

    # Inter-VLAN/LAN policy: deny-by-default; add explicit allows here
  }
}
EOF

  # Minimal bogons include placeholder
  cat > "$OUT_ROOT/etc/nftables.d/bogons.nft" <<'EOF'
add element inet winder_ultralight bogons_v4 {
  0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16,
  172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 192.168.0.0/16,
  198.18.0.0/15, 198.51.100.0/24, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4
}
EOF
fi

# shaping helper
if [[ "${SHAPING_ENABLE:-true}" == "true" ]]; then
  cat > "$OUT_ROOT/usr/local/sbin/ul_shaping.sh" <<EOF
#!/usr/bin/env bash
set -eo pipefail
WAN_IF="${1:-${WAN_IF_NAME}}"
EGRESS_KBIT="${2:-0}"
INGRESS_KBIT="${3:-0}"

if [[ "$EGRESS_KBIT" -eq 0 ]]; then
  EG=$(ethtool "$WAN_IF" 2>/dev/null | awk '/Speed:/ {gsub(/[^0-9]/,"",$2); print $2*1000}')
  EGRESS_KBIT=${EG:-1000000}
fi
if [[ "$INGRESS_KBIT" -eq 0 ]]; then
  IN=$EGRESS_KBIT
  INGRESS_KBIT=${IN}
fi

tc qdisc replace dev "$WAN_IF" root fq_codel
tc qdisc replace dev "$WAN_IF" handle ffff: ingress
tc filter replace dev "$WAN_IF" parent ffff: protocol all prio 50 u32 match u32 0 0 police rate ${INGRESS_KBIT}kbit burst 64k drop flowid :1
echo "fq_codel on $WAN_IF; ingress cap ${INGRESS_KBIT} kbit; egress fq_codel"
EOF
  chmod +x "$OUT_ROOT/usr/local/sbin/ul_shaping.sh"
fi

# minimal logrotate
mkdir -p "$OUT_ROOT/etc/logrotate.d"
cat > "$OUT_ROOT/etc/logrotate.d/home-secnet" <<'EOF'
/var/log/*.log {
  rotate 7
  daily
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
EOF

# stage SPA artifacts if present locally (no network)
mkdir -p "$OUT_ROOT/opt/spa"
if [[ -f "$SCRIPT_DIR/../router/spa-pq/target/release/home-secnet-spa-pq" ]]; then
  cp -f "$SCRIPT_DIR/../router/spa-pq/target/release/home-secnet-spa-pq" "$OUT_ROOT/opt/spa/home-secnet-spa-pq"
fi
if [[ -f "$SCRIPT_DIR/../clients/spa-pq-client/target/release/home-secnet-spa-pq-client" ]]; then
  cp -f "$SCRIPT_DIR/../clients/spa-pq-client/target/release/home-secnet-spa-pq-client" "$OUT_ROOT/opt/spa/home-secnet-spa-pq-client"
fi
for f in token.json token.sig pubkey.gpg cosign.pub cosign.bundle; do
  if [[ -f "$SCRIPT_DIR/../$f" ]]; then cp -f "$SCRIPT_DIR/../$f" "$OUT_ROOT/opt/spa/$f"; fi
done

# optional ultralight health helper
cat > "$OUT_ROOT/usr/local/sbin/ul_health.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "== nftables summary =="
if command -v nft >/dev/null 2>&1; then
  nft list ruleset | sed -n '1,120p' | sed 's/^/  /'
else
  echo "nft not installed"
fi
echo "== DNS =="
systemctl --no-pager --full status unbound 2>/dev/null | head -n 15 || true
systemctl --no-pager --full status dnsmasq 2>/dev/null | head -n 15 || true
echo "== Shaping =="
WAN_DEV=${1:-${WAN_IF_NAME}}
tc qdisc show dev "$WAN_DEV" || true
echo "== WireGuard (port closed by default) =="
ss -lunp | grep -E ':(51820)\s' || echo "WG not listening or port closed (expected until SPA)"
EOF
chmod +x "$OUT_ROOT/usr/local/sbin/ul_health.sh"

echo "[render] Ultralight render complete under $OUT_ROOT/."
