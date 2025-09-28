#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Central constants to keep scripts/docs aligned.

# nftables chains
readonly NFT_TABLE="inet"
readonly NFT_INPUT_CHAIN="filter"
readonly NFT_WG_SPA_ALLOW="wg_spa_allow"

# Binary install paths
readonly BIN_SPA_DAEMON="/usr/local/bin/home-secnet-spa-pq"
readonly BIN_SPA_CLIENT="/usr/local/bin/home-secnet-spa-pq-client"

export NFT_TABLE NFT_INPUT_CHAIN NFT_WG_SPA_ALLOW BIN_SPA_DAEMON BIN_SPA_CLIENT

