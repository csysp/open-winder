#!/usr/bin/env bash
# Logging helpers for Winder scripts. Do not log secrets.
# Usage: source this file near the top of scripts after enabling strict mode.

log_ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }

log_info()  { printf '%s [INFO]  %s\n' "$(log_ts)" "$*"; }
log_warn()  { printf '%s [WARN]  %s\n' "$(log_ts)" "$*" >&2; }
log_error() { printf '%s [ERROR] %s\n' "$(log_ts)" "$*" >&2; }

die() {
  local code=${1:-1}; shift || true
  log_error "${*:-fatal}"
  exit "$code"
}

run() {
  if [[ "${VERBOSE:-0}" == "1" ]]; then
    printf '+ %s\n' "$*"
  fi
  "$@"
}

