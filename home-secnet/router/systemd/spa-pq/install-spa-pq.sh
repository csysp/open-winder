#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

umask 077

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[spa-pq] must run as root" >&2
  exit 1
fi

echo "[spa-pq] Installing verified SPA daemon..."
# Prefer pre-staged binary (air-gapped). Otherwise require URL+SHA256 env.
BIN_DST="/usr/local/bin/home-secnet-spa-pq"
if [[ -f "/opt/router/spa/home-secnet-spa-pq" ]]; then
  install -m 0755 "/opt/router/spa/home-secnet-spa-pq" "$BIN_DST"
else
  : "${SPA_PQ_URL:?set SPA_PQ_URL to a version-pinned release URL}"
  : "${SPA_PQ_SHA256:?set SPA_PQ_SHA256 to the expected sha256}"
  # shellcheck disable=SC1091
  source /opt/router/systemd/lib/download.sh 2>/dev/null || true
  if ! command -v download_verified >/dev/null 2>&1; then
    # minimal inline fallback
    tmp="${BIN_DST}.tmp$$"; mkdir -p /usr/local/bin
    command -v curl >/dev/null 2>&1 || { echo "missing curl" >&2; exit 1; }
    command -v sha256sum >/dev/null 2>&1 || { echo "missing sha256sum" >&2; exit 1; }
    curl -fsSL "$SPA_PQ_URL" -o "$tmp"
    got="$(sha256sum "$tmp" | awk '{print $1}')"
    [[ "$got" == "$SPA_PQ_SHA256" ]] || { echo "checksum mismatch" >&2; rm -f "$tmp"; exit 1; }
    mv -f "$tmp" "$BIN_DST"; chmod 0755 "$BIN_DST"
  else
    download_verified "$SPA_PQ_URL" "$SPA_PQ_SHA256" "$BIN_DST"
    chmod 0755 "$BIN_DST"
  fi
fi
echo "[spa-pq] Installed $BIN_DST"
