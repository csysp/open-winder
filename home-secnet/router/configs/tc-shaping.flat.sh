#!/usr/bin/env bash
set -euo pipefail

echo "Configuring fq_codel on ${ROUTER_LAN_IF}"
tc qdisc replace dev "${ROUTER_LAN_IF}" root fq_codel || true
echo "Done tc shaping."

