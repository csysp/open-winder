#!/usr/bin/env bash
set -euo pipefail

echo "Testing SPA (Single Packet Authorization) configuration..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

if [[ "${SPA_ENABLE:-false}" == "false" ]]; then
  echo "SPA is disabled. Skipping SPA tests."
  exit 0
fi

echo "SPA is enabled. Checking configuration..."

# PQ‑KEM SPA only
if [[ "${SPA_MODE:-pqkem}" != "pqkem" ]]; then
  echo "ERROR: SPA_MODE must be 'pqkem' when SPA is enabled"
  exit 1
fi

echo "SPA mode: pqkem"
# Check PQ artifacts
if [[ ! -f "$ROOT_DIR/clients/spa-pq-client.json" ]]; then
  echo "WARNING: Missing clients/spa-pq-client.json (provide locally when using the client)"
fi
if [[ ! -f "$ROOT_DIR/render/spa/pq/psk.bin" ]]; then
  echo "WARNING: PSK not rendered locally; will be generated/applied on router"
fi
echo "PQ-KEM SPA config present. Use spa-pq-client to knock."

