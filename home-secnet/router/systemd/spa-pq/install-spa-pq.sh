#!/usr/bin/env bash
set -euo pipefail

echo "[spa-pq] Installing build prerequisites and building daemon..."
if ! command -v cargo >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y rustc cargo pkg-config build-essential
fi

cd /opt/router/spa-pq-src
cargo build --release
install -m 0755 target/release/home-secnet-spa-pq /usr/local/bin/home-secnet-spa-pq
echo "[spa-pq] Installed /usr/local/bin/home-secnet-spa-pq"

