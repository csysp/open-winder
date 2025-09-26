#!/usr/bin/env bash
set -euo pipefail

VERSION="${ADGUARD_VERSION:-latest}"
ARCH="linux_amd64"
INSTALL_DIR="/opt/adguard"
BIN="${INSTALL_DIR}/AdGuardHome"

mkdir -p "$INSTALL_DIR"

dl_latest() {
  local api="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
  local url
  url=$(curl -fsSL "$api" | grep -Eo "https.*AdGuardHome_${ARCH}\.tar\.gz" | head -n1)
  echo "$url"
}

dl_version() {
  local tag="$1"
  echo "https://github.com/AdguardTeam/AdGuardHome/releases/download/${tag}/AdGuardHome_${ARCH}.tar.gz"
}

echo "[adguard] Installing AdGuard Home (version: $VERSION)"
set -euo pipefail
apt-get update -y
apt-get install -y curl tar

URL=""
if [[ "$VERSION" == "latest" ]]; then
  URL=$(dl_latest)
else
  URL=$(dl_version "$VERSION")
fi

if [[ -z "$URL" ]]; then
  echo "[adguard] Could not determine download URL" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "[adguard] Downloading: $URL"
curl -fsSL "$URL" -o "$TMP/adguard.tar.gz"
tar -xzf "$TMP/adguard.tar.gz" -C "$TMP"
install -m 0755 "$TMP/AdGuardHome/AdGuardHome" "$BIN"
echo "[adguard] Installed to $BIN"
