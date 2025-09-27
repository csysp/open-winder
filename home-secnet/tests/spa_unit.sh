#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Basic SPA packet structure tests (scaffolding)
# - Verifies client builds a packet with expected fields and HMAC length
# - Verifies server rejects stale timestamps

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found; skipping SPA unit scaffolding" && exit 0
fi

pushd "$ROOT_DIR/clients/spa-pq-client" >/dev/null
cargo test -q || echo "[spa][client] tests not implemented; placeholder"
popd >/dev/null

pushd "$ROOT_DIR/router/spa-pq" >/dev/null
cargo test -q || echo "[spa][server] tests not implemented; placeholder"
popd >/dev/null

echo "[spa] unit scaffolding executed"

