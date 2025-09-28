#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Purpose: Apply pre-staged SPA artifacts in air-gapped mode
# Inputs: none
# Side effects: installs binaries/configs, enables SPA service

LOG() { echo "[spa-airgap] $*"; }
die() { echo "[spa-airgap][error] $*" >&2; exit 1; }

SRC_DIR="/opt/router/render/opt/spa"
BIN_DIR="/usr/local/bin"
DEST_CFG_DIR="/opt/spa"

REQUIRED_BIN="${SRC_DIR}/home-secnet-spa-pq"
OPTIONAL_CLIENT="${SRC_DIR}/home-secnet-spa-pq-client"
TOKEN_JSON="${SRC_DIR}/token.json"
TOKEN_SIG="${SRC_DIR}/token.sig"
PUBKEY_GPG="${SRC_DIR}/pubkey.gpg"

if [[ ! -x "$REQUIRED_BIN" || ! -f "$TOKEN_JSON" ]]; then
  die "missing required artifacts in ${SRC_DIR}"
fi

install -d -m 0755 "$DEST_CFG_DIR"

# Copy binaries
install -m 0755 "$REQUIRED_BIN" "$BIN_DIR/home-secnet-spa-pq"
if [[ -x "$OPTIONAL_CLIENT" ]]; then
  install -m 0755 "$OPTIONAL_CLIENT" "$BIN_DIR/home-secnet-spa-pq-client"
fi

# Copy tokens/signature
install -m 0644 "$TOKEN_JSON" "$DEST_CFG_DIR/token.json"
if [[ -f "$TOKEN_SIG" ]]; then
  install -m 0644 "$TOKEN_SIG" "$DEST_CFG_DIR/token.sig"
fi
if [[ -f "$PUBKEY_GPG" ]]; then
  install -m 0644 "$PUBKEY_GPG" "$DEST_CFG_DIR/pubkey.gpg"
fi

# Verify signature if both present
if [[ -f "$TOKEN_SIG" && -f "$PUBKEY_GPG" ]]; then
  if command -v gpg >/dev/null 2>&1; then
    gpg --import "$DEST_CFG_DIR/pubkey.gpg" >/dev/null 2>&1 || true
    if ! gpg --verify "$DEST_CFG_DIR/token.sig" "$DEST_CFG_DIR/token.json" >/dev/null 2>&1; then
      die "GPG verification failed"
    fi
    LOG "GPG signature verified"
  else
    LOG "gpg not present; skipping signature verify"
  fi
fi

# Verify sha256 if .sha256 present next to binaries
for f in "$REQUIRED_BIN" "$OPTIONAL_CLIENT"; do
  [[ -f "$f" ]] || continue
  if [[ -f "$f.sha256" ]]; then
    ( cd "$(dirname "$f")" && sha256sum -c "$(basename "$f").sha256" ) || die "sha256 failed for $f"
  fi
done

systemctl daemon-reload || true
systemctl enable --now home-secnet-spa-pq.service || die "failed to enable/start SPA service"

LOG "Applied air-gapped SPA artifacts"

