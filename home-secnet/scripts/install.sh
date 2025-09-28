#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: One-liner entrypoint to run the Winder setup wizard locally or from a pinned URL.
# Local mode: executes the repo's wizard.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: install.sh [--yes]
  Runs the Winder setup wizard for OpenWRT overlay rendering.

Flags:
  --yes     Assume yes on optional prompts where safe.

Environment:
  MODE=openwrt              Enforced by lib/env.sh
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi

# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"

if [[ ! -f "${SCRIPT_DIR}/wizard.sh" ]]; then
  echo "[install] wizard.sh not found. Ensure you are running from a cloned repo." >&2
  exit 1
fi

YES_FLAG=""
if [[ "${1:-}" == "--yes" ]]; then YES_FLAG="--yes"; fi

exec "${SCRIPT_DIR}/wizard.sh" ${YES_FLAG}

