#!/usr/bin/env bash
set -euo pipefail

echo "Testing SPA (Single Packet Authorization) configuration..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

if [[ "${SPA_ENABLE:-false}" == "false" ]]; then
  echo "SPA is disabled. Skipping SPA tests."
  exit 0
fi

echo "SPA is enabled. Checking configuration..."

# Check if SPA keys are set
if [[ "${SPA_MODE:-legacy}" == "pqkem" ]]; then
  echo "SPA mode: pqkem"
  # Check PQ artifacts
  if [[ ! -f "$ROOT_DIR/clients/spa-pq-client.json" ]]; then
    echo "ERROR: Missing clients/spa-pq-client.json"
    exit 1
  fi
  if [[ ! -f "$ROOT_DIR/render/spa/pq/psk.bin" ]]; then
    echo "WARNING: PSK not rendered locally; will be generated/applied on router"
  fi
  echo "PQ-KEM SPA config present. Use spa-pq-client to knock."
else
  # Legacy fwknop checks
  if [[ -z "${SPA_KEY:-}" ]]; then
    echo "ERROR: SPA_KEY is not set"
    exit 1
  fi
  if [[ -z "${SPA_HMAC_KEY:-}" ]]; then
    echo "ERROR: SPA_HMAC_KEY is not set"
    exit 1
  fi
  if [[ "$SPA_KEY" == "$SPA_HMAC_KEY" ]]; then
    echo "ERROR: SPA_KEY and SPA_HMAC_KEY are identical (security risk)"
    exit 1
  fi
  if [[ ! -f "$ROOT_DIR/clients/spa-client.conf" ]]; then
    echo "ERROR: SPA client configuration not found at clients/spa-client.conf"
    exit 1
  fi
  echo "SPA (fwknop) configuration validation passed."
fi
