#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'

BIN="/usr/local/bin/AdGuardHome"
echo "[adguard] Installing verified AdGuard Home binary..."
: "${ADGUARD_URL:?set ADGUARD_URL to version-pinned release URL (static binary tar.gz or binary)}"
: "${ADGUARD_SHA256:?set ADGUARD_SHA256 to expected sha256}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
command -v curl >/dev/null 2>&1 || { echo "missing curl" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "missing sha256sum" >&2; exit 1; }
curl -fsSL "$ADGUARD_URL" -o "$TMPDIR/pkg"
GOT=$(sha256sum "$TMPDIR/pkg" | awk '{print $1}')
[[ "$GOT" == "$ADGUARD_SHA256" ]] || { echo "[adguard] checksum mismatch" >&2; exit 1; }

# Handle both raw binary and tar.gz package forms
if file "$TMPDIR/pkg" | grep -qi 'gzip compressed data'; then
  tar -xzf "$TMPDIR/pkg" -C "$TMPDIR"
  BIN_SRC=$(find "$TMPDIR" -type f -name AdGuardHome | head -n1 || true)
  [[ -n "$BIN_SRC" ]] || { echo "[adguard] could not find AdGuardHome in archive" >&2; exit 1; }
  install -m 0755 "$BIN_SRC" "$BIN"
else
  install -m 0755 "$TMPDIR/pkg" "$BIN"
fi
echo "[adguard] Installed to $BIN"
