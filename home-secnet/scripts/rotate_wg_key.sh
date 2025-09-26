#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# shellcheck source=scripts/lib/log.sh
# shellcheck source=home-secnet/scripts/lib/log.sh
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"
if [[ -f "$LIB_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$LIB_PATH"
fi

usage() {
  cat <<USAGE
Rotate a WireGuard peer key and render updated configs.

Flags:
  --peer NAME     Required: peer name to rotate (matches client file prefix)
  --yes           Non-interactive; assume yes to prompts

Environment:
  ROOT_DIR        Repo root (auto-detected)
USAGE
}

YES=0
PEER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --peer) PEER="$2"; shift 2;;
    --yes) YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -z "$PEER" ]] && { log_error "--peer is required"; exit 2; }

# Paths
RENDER_WG="$ROOT_DIR/render/wg"
SERVER_CONF="$RENDER_WG/wg0.conf"
CLIENT_CONF="$ROOT_DIR/clients/${PEER}.conf"
ARCHIVE_DIR="$ROOT_DIR/clients/archive"
mkdir -p "$RENDER_WG" "$ARCHIVE_DIR"

if [[ ! -f "$SERVER_CONF" ]]; then
  log_error "Server config not found at $SERVER_CONF. Re-render router configs first."; exit 1
fi
if [[ ! -f "$CLIENT_CONF" ]]; then
  log_error "Client config not found at $CLIENT_CONF"; exit 1
fi

log_info "Generating new keypair for peer '$PEER'"
umask 077
NEW_PRIV=$(wg genkey)
NEW_PUB=$(printf '%s' "$NEW_PRIV" | wg pubkey)

# Confirm unless --yes provided
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Rotate key for peer '$PEER'? [y/N]: " ans
  case "$ans" in
    y|Y) ;; 
    *) log_info "Aborted."; exit 0;;
  esac
fi

# Update server conf atomically
TMP_SERVER="${SERVER_CONF}.tmp"
awk -v peer="$PEER" -v pub="$NEW_PUB" '
  BEGIN{inpeer=0}
  $0 ~ "\[Peer\]" {inpeer=0}
  inpeer==1 && $1=="PublicKey" { $3=pub; print; next }
  { print }
  $0 ~ "\[Peer\]" {print; next}
  $0 ~ "# PEER:"peer"$" { inpeer=1 }
' "$SERVER_CONF" > "$TMP_SERVER"
mv "$TMP_SERVER" "$SERVER_CONF"

# Update client conf atomically
TMP_CLIENT="${CLIENT_CONF}.tmp"
awk -v priv="$NEW_PRIV" '
  $1=="PrivateKey" { $3=priv; print; next }
  { print }
' "$CLIENT_CONF" > "$TMP_CLIENT"
mv "$TMP_CLIENT" "$CLIENT_CONF"

# Archive hint for old key rotation window (manual remove after grace)
cp -a "$CLIENT_CONF" "$ARCHIVE_DIR/${PEER}-$(date +%Y%m%d%H%M%S).conf"
log_info "Rotated peer '$PEER'. Distribute updated client config: $CLIENT_CONF"

echo "NOTE: Apply updated server config on the router (wg setconf wg0 /etc/wireguard/wg0.conf) and restart wg if needed."
