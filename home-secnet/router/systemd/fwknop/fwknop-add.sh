#!/usr/bin/env bash
set -euo pipefail

SRC_IP="$1"
SET_NAME="wg_spa"
TABLE="inet"
FAMILY="filter"

# Add source IP to nftables set with timeout
# Quote the set literal to avoid ShellCheck brace warnings while keeping nft syntax
nft add element "${TABLE}" "${FAMILY}" "${SET_NAME}" "{ ${SRC_IP} timeout ${SPA_TIMEOUT}s }" || true
echo "Added ${SRC_IP} to ${SET_NAME} for ${SPA_TIMEOUT}s"
