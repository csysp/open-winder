#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Verified downloads with SHA256. Usage: download_verified URL SHA256 OUT

download_verified() {
  local url="$1"; local sha256="$2"; local out="$3"
  command -v curl >/dev/null 2>&1 || { echo "missing curl" >&2; exit 1; }
  command -v sha256sum >/dev/null 2>&1 || { echo "missing sha256sum" >&2; exit 1; }
  local tmp
  tmp="${out}.tmp$$"
  mkdir -p "$(dirname "$out")"
  curl -fsSL "$url" -o "$tmp"
  local got
  got="$(sha256sum "$tmp" | awk '{print $1}')"
  if [[ "$got" != "$sha256" ]]; then
    rm -f "$tmp"
    echo "[download] checksum mismatch for $url" >&2
    echo "[download] expected $sha256 got $got" >&2
    exit 1
  fi
  mv -f "$tmp" "$out"
}

export -f download_verified

