#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Safe, consistent environment loader for Winder scripts.
# Loads .env.example then .env (if present), enforces MODE and required vars.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/lib -> project root is two levels up
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

load_env() {
  set +u
  # Load defaults first, then user overrides
  [[ -f "$ROOT_DIR/.env.example" ]] && source "$ROOT_DIR/.env.example"
  [[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"
  set -u
}

require_vars() {
  local missing=()
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then
      missing+=("$v")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "[env] missing required variables: ${missing[*]}" >&2
    echo "[env] run: home-secnet/scripts/setup_env.sh" >&2
    exit 1
  fi
}

enforce_mode() {
  local expected="openwrt"
  if [[ -z "${MODE:-}" ]]; then
    export MODE="$expected"
  fi
  if [[ "$MODE" != "$expected" ]]; then
    echo "[env] MODE=$MODE not supported in this branch; expected $expected" >&2
    exit 1
  fi
}

# Entry
load_env
enforce_mode

export -f load_env require_vars enforce_mode
