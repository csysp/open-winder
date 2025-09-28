#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'

ARCH="linux-amd64"
BIN="/usr/local/bin/hysteria"

echo "[hysteria] Installing verified binary..."
: "${HYSTERIA_URL:?set HYSTERIA_URL to a version-pinned release URL}"
: "${HYSTERIA_SHA256:?set HYSTERIA_SHA256 to expected sha256}"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
command -v curl >/dev/null 2>&1 || { echo "missing curl" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "missing sha256sum" >&2; exit 1; }
curl -fsSL "$HYSTERIA_URL" -o "$TMP"
GOT=$(sha256sum "$TMP" | awk '{print $1}')
[[ "$GOT" == "$HYSTERIA_SHA256" ]] || { echo "[hysteria] checksum mismatch" >&2; exit 1; }
install -m 0755 "$TMP" "$BIN"
echo "[hysteria] Installed to $BIN"
