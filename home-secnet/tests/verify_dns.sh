#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"
dig +short @"${GW_TRUSTED}" example.com || true
dig +short @10.66.66.1 example.com || true
echo "DNS queries attempted (check outputs)."
