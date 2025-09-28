#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Hardened traffic shaping for flat LAN setups
# - Egress shaping on WAN using CAKE (preferred) or HTB+fq_codel fallback
# - Optional ingress shaping via IFB
# - fq_codel on LAN as leaf for local buffer control
#
# Inputs (env):
#   ROUTER_WAN_IF, ROUTER_LAN_IF
#   SHAPING_EGRESS_KBIT  (required to enable egress shaping)
#   SHAPING_INGRESS_KBIT (optional; enables IFB ingress shaping)
#   DSCP_ENABLE=false    (optional; if true, use diffserv4)
#   DRY_RUN=1            (optional; print commands only)

run() { if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "+ $*"; else eval "$*"; fi; }
die() { echo "[tc] $*" >&2; exit 1; }

command -v tc >/dev/null 2>&1 || die "tc not found"

WAN="${ROUTER_WAN_IF:-}"
LAN="${ROUTER_LAN_IF:-}"
[[ -n "$WAN" && -n "$LAN" ]] || die "ROUTER_WAN_IF/ROUTER_LAN_IF required"

# Egress shaping (WAN)
EGRESS_KBIT="${SHAPING_EGRESS_KBIT:-0}"
INGRESS_KBIT="${SHAPING_INGRESS_KBIT:-0}"
DIFFSERV_ARG="besteffort"
[[ "${DSCP_ENABLE:-false}" == "true" ]] && DIFFSERV_ARG="diffserv4"

has_cake=false
if lsmod 2>/dev/null | grep -q '^sch_cake'; then has_cake=true; fi
if [[ "$has_cake" == false ]]; then
  # attempt to load
  run modprobe sch_cake 2>/dev/null || true
  lsmod | grep -q '^sch_cake' && has_cake=true || has_cake=false
fi

if [[ "$EGRESS_KBIT" =~ ^[0-9]+$ && "$EGRESS_KBIT" -gt 0 ]]; then
  echo "[tc] Configure egress on $WAN (${EGRESS_KBIT}kbit)"
  if [[ "$has_cake" == true ]]; then
    run tc qdisc replace dev "$WAN" root cake bandwidth "${EGRESS_KBIT}"kbit ${DIFFSERV_ARG} nat
  else
    # HTB root + fq_codel leaf
    run tc qdisc replace dev "$WAN" root handle 1: htb default 10
    run tc class replace dev "$WAN" parent 1: classid 1:10 htb rate "${EGRESS_KBIT}"kbit ceil "${EGRESS_KBIT}"kbit
    run tc qdisc replace dev "$WAN" parent 1:10 handle 10: fq_codel ecn
  fi
else
  echo "[tc] Egress shaping disabled (SHAPING_EGRESS_KBIT not set)"
  run tc qdisc del dev "$WAN" root 2>/dev/null || true
fi

# Ingress shaping via IFB (optional)
if [[ "$INGRESS_KBIT" =~ ^[0-9]+$ && "$INGRESS_KBIT" -gt 0 ]]; then
  echo "[tc] Configure ingress on $WAN via ifb0 (${INGRESS_KBIT}kbit)"
  run modprobe ifb || die "missing ifb"
  run ip link add ifb0 type ifb 2>/dev/null || true
  run ip link set dev ifb0 up
  run tc qdisc replace dev "$WAN" handle ffff: ingress
  run tc filter replace dev "$WAN" parent ffff: matchall action mirred egress redirect dev ifb0
  if [[ "$has_cake" == true ]]; then
    run tc qdisc replace dev ifb0 root cake bandwidth "${INGRESS_KBIT}"kbit ${DIFFSERV_ARG}
  else
    run tc qdisc replace dev ifb0 root handle 1: htb default 10
    run tc class replace dev ifb0 parent 1: classid 1:10 htb rate "${INGRESS_KBIT}"kbit ceil "${INGRESS_KBIT}"kbit
    run tc qdisc replace dev ifb0 parent 1:10 handle 10: fq_codel ecn
  fi
else
  echo "[tc] Ingress shaping disabled"
  run tc qdisc del dev "$WAN" ingress 2>/dev/null || true
  run tc qdisc del dev ifb0 root 2>/dev/null || true
  run ip link del ifb0 2>/dev/null || true
fi

# LAN fq_codel (leaf)
echo "[tc] fq_codel on $LAN"
run tc qdisc replace dev "$LAN" root fq_codel ecn

echo "[tc] qdisc summary"
tc -s qdisc show dev "$WAN" || true
tc -s qdisc show dev "$LAN" || true
tc -s qdisc show dev ifb0 2>/dev/null || true
