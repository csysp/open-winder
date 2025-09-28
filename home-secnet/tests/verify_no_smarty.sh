#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Fail if any Smarty-style templates or .tpl files exist.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

found=0
if rg -n "\\.tpl$" -g "**/*" >/dev/null 2>&1; then
  echo "[verify] Found .tpl files; migrate to .template and envsubst." >&2
  rg -n "\\.tpl$" -g "**/*" || true
  found=1
fi
if rg -n "\{\$[A-Za-z_][A-Za-z0-9_]*\}|\{if |\{foreach |\{include " -S -g "**/*" >/dev/null 2>&1; then
  echo "[verify] Found Smarty-like tokens; remove and use \\${VAR} with envsubst." >&2
  rg -n "\{\$[A-Za-z_][A-Za-z0-9_]*\}|\{if |\{foreach |\{include " -S -g "**/*" || true
  found=1
fi

if [[ "$found" -ne 0 ]]; then
  exit 1
fi
echo "[verify] No Smarty templates detected."

