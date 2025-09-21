#!/usr/bin/env bash
set -euo pipefail

# Simple fq_codel on VLAN subinterfaces; optional rate limit via tbf if RATE env provided per VLAN

IFACES=("${ROUTER_LAN_IF}.${VLAN_TRUSTED}" "${ROUTER_LAN_IF}.${VLAN_IOT}" "${ROUTER_LAN_IF}.${VLAN_GUEST}" "${ROUTER_LAN_IF}.${VLAN_LAB}")

for IF in "${IFACES[@]}"; do
  echo "Configuring fq_codel on $IF"
  tc qdisc replace dev "$IF" root fq_codel || true
done

echo "Done tc shaping."

