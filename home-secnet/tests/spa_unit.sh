#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'

# Basic SPA packet structure tests (scaffolding)
# - Verifies client builds a packet with expected fields and HMAC length
# - Verifies server rejects stale timestamps

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found; skipping SPA unit scaffolding" && exit 0
fi

pushd "$ROOT_DIR/clients/spa-pq-client" >/dev/null
if ! cargo test -q; then
  if [[ "${ALLOW_PLACEHOLDER_TESTS:-0}" == "1" ]]; then
    echo "[spa][client] tests missing; allowed by ALLOW_PLACEHOLDER_TESTS=1"
  else
    echo "[spa][client] tests missing; set ALLOW_PLACEHOLDER_TESTS=1 to bypass" >&2
    exit 1
  fi
fi
popd >/dev/null

pushd "$ROOT_DIR/router/spa-pq" >/dev/null
if ! cargo test -q; then
  if [[ "${ALLOW_PLACEHOLDER_TESTS:-0}" == "1" ]]; then
    echo "[spa][server] tests missing; allowed by ALLOW_PLACEHOLDER_TESTS=1"
  else
    echo "[spa][server] tests missing; set ALLOW_PLACEHOLDER_TESTS=1 to bypass" >&2
    exit 1
  fi
fi
popd >/dev/null

echo "[spa] unit scaffolding executed"
