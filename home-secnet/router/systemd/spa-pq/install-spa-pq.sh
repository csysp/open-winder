#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

umask 077

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[spa-pq] must run as root" >&2
  exit 1
fi

echo "[spa-pq] Installing build prerequisites and building daemon..."
if ! command -v cargo >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y -q
  apt-get install -y -q --no-install-recommends rustc cargo pkg-config build-essential ca-certificates
fi

cd /opt/router/spa-pq-src
cargo build --release
install -m 0755 target/release/home-secnet-spa-pq /usr/local/bin/home-secnet-spa-pq
echo "[spa-pq] Installed /usr/local/bin/home-secnet-spa-pq"
