#!/usr/bin/env bash
set -euo pipefail

VERSION="${HYSTERIA_VERSION:-latest}"
ARCH="linux-amd64"
INSTALL_DIR="/opt/hysteria"
BIN="${INSTALL_DIR}/hysteria"

mkdir -p "$INSTALL_DIR"
set -euo pipefail
apt-get update -y
apt-get install -y curl tar

dl_latest() {
  local api="https://api.github.com/repos/apernet/hysteria/releases/latest"
  curl -fsSL "$api" | grep -Eo "https.*hysteria-${ARCH}\.tar\.gz" | head -n1
}

dl_version() {
  local tag="$1"
  echo "https://github.com/apernet/hysteria/releases/download/${tag}/hysteria-${ARCH}.tar.gz"
}

URL=""
if [[ "$VERSION" == "latest" ]]; then
  URL=$(dl_latest)
else
  URL=$(dl_version "$VERSION")
fi

if [[ -z "$URL" ]]; then
  echo "[hysteria] Could not determine download URL" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "[hysteria] Downloading: $URL"
curl -fsSL "$URL" -o "$TMP/hy.tar.gz"
tar -xzf "$TMP/hy.tar.gz" -C "$TMP"
install -m 0755 "$TMP/hysteria" "$BIN"
echo "[hysteria] Installed to $BIN"
