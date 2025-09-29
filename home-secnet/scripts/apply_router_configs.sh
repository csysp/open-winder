#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail; IFS=$'\n\t'
# Purpose: Push rendered configs to Router VM and apply them safely.
# Inputs: .env via scripts/lib/env.sh; VERBOSE (optional)
# Outputs: none
# Side effects: Modifies Router VM config files/services.

usage() {
  cat <<'USAGE'
Usage: apply_router_configs.sh
  Copies home-secnet/render/ to Router VM and applies configs.

Environment:
  VERBOSE=1   Enable verbose logging
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/lib/log.sh" ]] && source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"

log_info "[09] Pushing configs into Router VM and applying..."
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Determine Router VM IP via QEMU agent (expects DHCP on WAN or console access)
ROUTER_IP="${ROUTER_IP:-}" # allow override
if [[ -z "${ROUTER_IP}" ]]; then
  if qm agent $ROUTER_VM_ID network-get-interfaces >/dev/null 2>&1; then
    ROUTER_IP=$(qm agent $ROUTER_VM_ID network-get-interfaces | awk -F'"' '/"ip-address":/ {print $4}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1 || echo "")
    if [[ -z "${ROUTER_IP:-}" ]]; then log_warn "[09] Could not determine Router IP via qemu-guest-agent"; fi
  fi
fi
if [[ -z "${ROUTER_IP}" ]]; then
  read -r -p "[09] Router VM IP not detected. Enter Router IP: " ROUTER_IP
  if [[ -z "$ROUTER_IP" ]]; then echo "[09] Router IP is required." >&2; exit 1; fi
fi

echo "[09] Using Router VM IP: $ROUTER_IP"

RUSER=${ROUTER_ADMIN_USER}

ssh -o StrictHostKeyChecking=accept-new ${RUSER}@${ROUTER_IP} "sudo mkdir -p /opt/router && sudo chown \$(id -un):\$(id -gn) /opt/router"
rsync -av --delete "$ROOT_DIR/render/router/configs/" ${RUSER}@${ROUTER_IP}:/opt/router/
rsync -av "$ROOT_DIR/router/systemd/" ${RUSER}@${ROUTER_IP}:/opt/router/systemd/
rsync -av "$ROOT_DIR/router/hardening/" ${RUSER}@${ROUTER_IP}:/opt/router/hardening/
rsync -av "$ROOT_DIR/router/cloudinit/" ${RUSER}@${ROUTER_IP}:/opt/router/cloudinit/
if [[ -d "$ROOT_DIR/render/spa/pq" ]]; then
  rsync -av "$ROOT_DIR/render/spa/pq/" ${RUSER}@${ROUTER_IP}:/opt/router/spa-pq/
fi
  # no longer building on router; spa-pq-src sync removed
if [[ -d "$ROOT_DIR/render/router/systemd" ]]; then
  rsync -av "$ROOT_DIR/render/router/systemd/" ${RUSER}@${ROUTER_IP}:/opt/router/systemd/rendered/
fi

ssh ${RUSER}@${ROUTER_IP} "USE_VLANS='${USE_VLANS}' ROUTER_LAN_IF='${ROUTER_LAN_IF}' VLAN_TRUSTED='${VLAN_TRUSTED}' VLAN_IOT='${VLAN_IOT}' VLAN_GUEST='${VLAN_GUEST}' VLAN_LAB='${VLAN_LAB}' DISABLE_USB_STORAGE='${DISABLE_USB_STORAGE}' HARDEN_AUDITD='${HARDEN_AUDITD}' INSTALL_AIDE='${INSTALL_AIDE}' FAIL2BAN_ENABLE='${FAIL2BAN_ENABLE}' ADGUARD_VERSION='${ADGUARD_VERSION}' HYSTERIA_VERSION='latest' RSYSLOG_FORWARD_ENABLE='${RSYSLOG_FORWARD_ENABLE:-false}' RSYSLOG_REMOTE='${RSYSLOG_REMOTE:-}' SPA_PQ_VERSION='${SPA_PQ_VERSION:-latest}' SPA_PQ_SIG_URL='${SPA_PQ_SIG_URL:-}' bash -s" <<'EOSSH'
set -euo pipefail
sudo mkdir -p /etc/netplan /etc/wireguard
# Backups with timestamp
ts=$(date +%s)
for f in /etc/netplan/99-router.yaml /etc/wireguard/wg0.conf /etc/nftables.conf /etc/dhcp/dhcpd.conf /etc/unbound/unbound.conf /etc/suricata/suricata.yaml; do
  if [[ -f "$f" ]]; then sudo cp -a "$f" "$f.bak-$ts"; fi
done

sudo cp /opt/router/netplan.yaml /etc/netplan/99-router.yaml
if [[ -f /opt/router/wg0.conf ]]; then
  sudo cp /opt/router/wg0.conf /etc/wireguard/wg0.conf
  sudo chmod 600 /etc/wireguard/wg0.conf
fi
sudo cp /opt/router/nftables.conf /etc/nftables.conf
sudo cp /opt/router/dhcpd.conf /etc/dhcp/dhcpd.conf
if [[ -f /opt/router/wg1.conf ]]; then
  sudo cp /opt/router/wg1.conf /etc/wireguard/wg1.conf
fi

# DHCP interfaces default
if [[ "${USE_VLANS}" == "true" ]]; then
  # Build VLAN interface list dynamically from VLAN IDs
  V_IFACES=()
  for vid in "${VLAN_TRUSTED}" "${VLAN_IOT}" "${VLAN_GUEST}" "${VLAN_LAB}"; do
    iface="${ROUTER_LAN_IF}.${vid}"
    if [[ -e "/sys/class/net/${iface}" ]]; then V_IFACES+=("$iface"); fi
  done
  IFACES="${V_IFACES[*]}"
else
  IFACES="${ROUTER_LAN_IF}"
fi
echo "INTERFACESv4=\"$IFACES\"" | sudo tee /etc/default/isc-dhcp-server >/dev/null

if [[ -f /opt/router/unbound.conf ]]; then
  sudo mkdir -p /etc/unbound
  sudo cp /opt/router/unbound.conf /etc/unbound/unbound.conf
fi
if [[ -f /opt/router/adguard-home.yaml ]]; then
  sudo mkdir -p /opt/adguard
  sudo cp /opt/router/adguard-home.yaml /opt/adguard/AdGuardHome.yaml
fi
if [[ -f /opt/router/hysteria2.yaml ]]; then
  sudo mkdir -p /etc/hysteria /opt/hysteria
  sudo cp /opt/router/hysteria2.yaml /etc/hysteria/config.yaml
fi
sudo cp /opt/router/suricata.yaml /etc/suricata/suricata.yaml
sudo install -m 0755 /opt/router/tc-shaping.sh /opt/router/tc-shaping.sh
rm -f /etc/rsyslog.d/90-remote.conf 2>/dev/null || echo "[09] no prior rsyslog remote config" >&2
if [[ -f /opt/router/rsyslog-secure.conf ]]; then
  sudo cp /opt/router/rsyslog-secure.conf /etc/rsyslog.d/99-secure.conf
  sudo systemctl restart rsyslog
fi

# Install daily security maintenance timers
sudo install -d -m 0755 /opt/router/security
if [[ -d /opt/router/systemd/security && -n "$(ls -A /opt/router/systemd/security 2>/dev/null)" ]]; then
  sudo cp -a /opt/router/systemd/security/*.sh /opt/router/security/
  sudo chmod +x /opt/router/security/*.sh
fi
sudo cp -a /opt/router/systemd/security/*.service /etc/systemd/system/
sudo cp -a /opt/router/systemd/security/*.timer /etc/systemd/system/
sudo cp -a /opt/router/systemd/adguard/adguardhome.service /etc/systemd/system/
sudo cp -a /opt/router/systemd/adguard/install-adguard.sh /opt/adguard/install-adguard.sh
sudo chmod +x /opt/adguard/install-adguard.sh
sudo cp -a /opt/router/systemd/hysteria/hysteria.service /etc/systemd/system/
sudo cp -a /opt/router/systemd/hysteria/install-hysteria.sh /opt/hysteria/install-hysteria.sh
sudo chmod +x /opt/hysteria/install-hysteria.sh
echo "[router] Email alerts disabled; skipping mail setup."
sudo systemctl daemon-reload
sudo systemctl enable --now home-secnet-daily-update.timer
sudo systemctl enable --now home-secnet-daily-lynis.timer
sudo systemctl enable --now home-secnet-daily-rootkit.timer
sudo systemctl enable --now home-secnet-daily-malware.timer

# Switch DNS stack if AdGuard is selected
if [[ -f /opt/adguard/AdGuardHome.yaml ]]; then
  echo "[router] DNS stack: AdGuard Home"
  # Install AdGuard Home if binary missing
  if [[ ! -x /opt/adguard/AdGuardHome ]]; then
    sudo ADGUARD_VERSION="${ADGUARD_VERSION:-latest}" /opt/adguard/install-adguard.sh
  fi
  # Stop unbound if running and enable AdGuard
  sudo systemctl disable --now unbound 2>/dev/null || echo "[09] unbound not active" >&2
  sudo systemctl enable --now adguardhome.service
else
  echo "[router] DNS stack: Unbound"
  sudo systemctl enable --now unbound
  sudo systemctl disable --now adguardhome.service 2>/dev/null || echo "[09] AdGuard not active" >&2
fi

# Start QUIC wrapper if configured
if [[ -f /etc/hysteria/config.yaml ]]; then
  if [[ ! -x /opt/hysteria/hysteria ]]; then
    sudo HYSTERIA_VERSION=latest /opt/hysteria/install-hysteria.sh
  fi
  # Generate self-signed cert if missing
  if [[ ! -f /etc/hysteria/server.crt || ! -f /etc/hysteria/server.key ]]; then
    if ! sudo apt-get update -y; then echo "[09] apt-get update failed on router" >&2; fi
    if ! sudo apt-get install -y openssl; then echo "[09] install openssl failed on router" >&2; fi
    sudo openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=${WRAP_DOMAIN:-hysteria.local}" -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt
    sudo chmod 600 /etc/hysteria/server.key
  fi
  sudo systemctl enable --now hysteria.service
fi

# Configure SPA gating if enabled (only when access.conf is present)
if [[ "${SPA_ENABLE}" == "true" ]]; then
  if [[ "${SPA_MODE:-pqkem}" == "pqkem" ]]; then
    echo "[router] Configuring PQ-KEM SPA daemon"
    # Ensure nftables table/chain as a safety net (nftables.conf should already include these)
    sudo nft list table inet filter >/dev/null 2>&1 || sudo nft add table inet filter || echo "[09] failed to add nft table inet filter" >&2
    # Create chain if missing
    sudo nft list chain inet filter wg_spa_allow >/dev/null 2>&1 || sudo nft add chain inet filter wg_spa_allow '{ }' || echo "[09] failed to add chain wg_spa_allow" >&2
    # Ensure jump rule exists in input chain (idempotent)
    if ! sudo nft list chain inet filter input | grep -q "udp dport ${WG_PORT} jump wg_spa_allow"; then
      sudo nft insert rule inet filter input udp dport ${WG_PORT} jump wg_spa_allow
    fi
    # Create service user
    if ! id -u winder-spa >/dev/null 2>&1; then
      sudo useradd --system --no-create-home --shell /usr/sbin/nologin winder-spa || echo "[09] user winder-spa exists" >&2
    fi
    # Fetch prebuilt, trusted SPA binary from GitHub Releases
    SPA_VER="${SPA_PQ_VERSION:-latest}"
    if [[ "$SPA_VER" == "latest" ]]; then
      echo "[09] WARNING: SPA_PQ_VERSION not set; using 'latest' (non-reproducible). Set a tagged version for reproducibility." >&2
    fi
    ARCH_BIN="home-secnet-spa-pq"
    DL_URL="https://github.com/csysp/winder/releases/download/${SPA_VER}/${ARCH_BIN}"
    DL_SHA="${DL_URL}.sha256"
    tmpd=$(mktemp -d)
    trap 'rm -rf "$tmpd"' EXIT
    curl -fsSL "$DL_URL" -o "$tmpd/$ARCH_BIN"
    curl -fsSL "$DL_SHA" -o "$tmpd/$ARCH_BIN.sha256"
    # Optional GPG verification of checksum file
    if [[ -n "${SPA_PQ_SIG_URL:-}" && -f /etc/spa/pubkey.gpg ]]; then
      curl -fsSL "${SPA_PQ_SIG_URL}" -o "$tmpd/$ARCH_BIN.sha256.asc" || echo "[09] could not fetch signature; proceeding without GPG verify" >&2
      if [[ -s "$tmpd/$ARCH_BIN.sha256.asc" ]]; then
        gpg --import /etc/spa/pubkey.gpg || echo "[09] GPG import failed; checksum verification only" >&2
        gpg --verify "$tmpd/$ARCH_BIN.sha256.asc" "$tmpd/$ARCH_BIN.sha256"
      fi
    fi
    (cd "$tmpd" && sha256sum -c "$ARCH_BIN.sha256")
    sudo install -m 0755 "$tmpd/$ARCH_BIN" /usr/local/bin/home-secnet-spa-pq
    # Install secrets
    sudo mkdir -p /etc/spa
    if [[ -f /opt/router/spa-pq/psk.bin ]]; then
      sudo install -m 0600 /opt/router/spa-pq/psk.bin /etc/spa/psk.bin
    fi
    if [[ -f /opt/router/spa-pq/kem_priv.bin && -f /opt/router/spa-pq/kem_pub.bin ]]; then
      sudo install -m 0600 /opt/router/spa-pq/kem_priv.bin /etc/spa/kem_priv.bin
      sudo install -m 0644 /opt/router/spa-pq/kem_pub.bin /etc/spa/kem_pub.bin
    else
      # Generate on router if not provided
      if command -v /usr/local/bin/home-secnet-spa-pq >/dev/null 2>&1; then
        sudo /usr/local/bin/home-secnet-spa-pq gen-keys --priv-out /etc/spa/kem_priv.bin --pub-out /etc/spa/kem_pub.bin
      fi
    fi
    # Install systemd unit
    if [[ -f /opt/router/systemd/rendered/spa-pq.service ]]; then
      sudo cp /opt/router/systemd/rendered/spa-pq.service /etc/systemd/system/spa-pq.service
    else
      sudo cp /opt/router/systemd/spa-pq/spa-pq.service.template /etc/systemd/system/spa-pq.service
      # Replace placeholders via envsubst-like bash here-doc if needed
      sudo bash -lc "sed -i -e 's/\${SPA_PQ_PORT}/${SPA_PQ_PORT}/g' -e 's/\${WG_PORT}/${WG_PORT}/g' -e 's#\${SPA_PQ_PSK_FILE}#${SPA_PQ_PSK_FILE}#g' -e 's/\${SPA_PQ_OPEN_SECS}/${SPA_PQ_OPEN_SECS}/g' -e 's/\${SPA_PQ_WINDOW_SECS}/${SPA_PQ_WINDOW_SECS}/g' /etc/systemd/system/spa-pq.service"
    fi
    sudo systemctl daemon-reload
    sudo systemctl enable --now spa-pq.service
    # Ensure fwknopd is stopped if previously installed
    sudo systemctl disable --now fwknopd 2>/dev/null || echo "[09] fwknopd not present" >&2
  fi
fi

sudo netplan apply
sudo nft -f /etc/nftables.conf
sudo systemctl enable --now nftables
sudo systemctl enable --now isc-dhcp-server
if [[ -f /etc/unbound/unbound.conf ]]; then
  sudo systemctl enable --now unbound
fi
if [[ -f /etc/wireguard/wg0.conf ]]; then
  sudo systemctl enable --now wg-quick@wg0
fi
if [[ -f /etc/wireguard/wg1.conf ]]; then
  sudo systemctl enable --now wg-quick@wg1
fi
sudo systemctl enable --now suricata

# Apply hardening: sysctl, modprobe blacklist, ssh, login defs, banner, profile
sudo mkdir -p /etc/sysctl.d /etc/modprobe.d /etc/security/limits.d /etc/profile.d /etc/home-secnet
sudo cp /opt/router/hardening/sysctl.conf /etc/sysctl.d/99-home-secnet.conf
sudo cp /opt/router/hardening/modprobe-blacklist.conf /etc/modprobe.d/blacklist-home-secnet.conf
sudo cp /opt/router/hardening/profile.d-home-secnet.sh /etc/profile.d/99-home-secnet.sh
sudo cp /opt/router/hardening/issue /etc/issue
sudo cp /opt/router/hardening/issue /etc/issue.net
sudo sysctl --system || echo "[09] sysctl reload returned non-zero" >&2
# Optional disable usb-storage
if [[ "${DISABLE_USB_STORAGE}" == "true" ]]; then
  echo 'install usb-storage /bin/false' | sudo tee -a /etc/modprobe.d/blacklist-home-secnet.conf >/dev/null
fi
# SSH hardening
ROUTER_ADMIN_USER="$ROUTER_ADMIN_USER" bash /opt/router/hardening/sshd_hardening.sh || echo "[09] sshd hardening script returned non-zero" >&2

# Install recommended packages
sudo apt-get update -y
sudo apt-get install -y libpam-tmpdir libpam-pwquality lynis rkhunter chkrootkit clamav-daemon clamav-freshclam
sudo systemctl enable --now clamav-freshclam || echo "[09] freshclam enable/start failed" >&2
if [[ "${HARDEN_AUDITD}" == "true" ]]; then
  sudo apt-get install -y auditd audispd-plugins
  sudo systemctl enable --now auditd || echo "[09] auditd enable/start failed" >&2
fi
if [[ "${INSTALL_AIDE}" == "true" ]]; then
  sudo apt-get install -y aide
  sudo aideinit || echo "[09] aideinit returned non-zero" >&2
fi
if [[ "${FAIL2BAN_ENABLE}" == "true" ]]; then
  sudo apt-get install -y fail2ban
  echo -e "[sshd]\nenabled = true\nmaxretry = 3\nbantime = 1h" | sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null
  sudo systemctl enable --now fail2ban || echo "[09] fail2ban enable/start failed" >&2

# Ultralight-specific applies
if [[ -f /etc/nftables.d/ultralight.nft ]]; then
  # Create table if missing, then load our chains/sets without flushing global ruleset
  if ! sudo nft list tables | grep -q 'inet winder_ultralight'; then
    sudo nft add table inet winder_ultralight || { echo "[09] failed to add nft table winder_ultralight" >&2; exit 1; }
  fi
  sudo nft -f /etc/nftables.d/ultralight.nft || echo "[09] applying ultralight nftables failed" >&2
  # Load bogons set elements if present
  if [[ -f /etc/nftables.d/bogons.nft ]]; then
    sudo nft -f /etc/nftables.d/bogons.nft || echo "[09] applying bogons set failed" >&2
  fi
  # Ensure persistence via /etc/nftables.conf include
  if [[ -f /etc/nftables.conf ]]; then
    if ! grep -q '^include "/etc/nftables.d/ultralight.nft"' /etc/nftables.conf; then
      echo 'include "/etc/nftables.d/ultralight.nft"' | sudo tee -a /etc/nftables.conf >/dev/null || { echo "[09] failed to persist ultralight include" >&2; exit 1; }
    fi
    if [[ -f /etc/nftables.d/bogons.nft ]] && ! grep -q '^include "/etc/nftables.d/bogons.nft"' /etc/nftables.conf; then
      echo 'include "/etc/nftables.d/bogons.nft"' | sudo tee -a /etc/nftables.conf >/dev/null || { echo "[09] failed to persist bogons include" >&2; exit 1; }
    fi
  fi
  sudo systemctl enable --now nftables || echo "[09] enabling nftables failed" >&2
fi

if [[ "${ULTRALIGHT_MODE:-false}" != "true" && "${ULTRALIGHT_EXPERIMENTAL:-0}" != "1" ]]; then
  echo "[09] Ultralight disabled (future addition)"
fi

if [[ "${DHCP_STACK:-dnsmasq}" == "dnsmasq" ]]; then
  sudo apt-get update -y && sudo apt-get install -y dnsmasq
  sudo install -m 0644 /opt/router/render/etc/dnsmasq.d/home-secnet.conf /etc/dnsmasq.d/home-secnet.conf || echo "[09] dnsmasq config install failed" >&2
  sudo systemctl enable --now dnsmasq || echo "[09] enabling dnsmasq failed" >&2
fi

if [[ "${DNS_STACK:-adguard}" == "unbound" ]]; then
  sudo apt-get update -y && sudo apt-get install -y unbound ca-certificates
  sudo install -m 0644 /opt/router/render/etc/unbound/unbound.conf /etc/unbound/unbound.conf || echo "[09] unbound config install failed" >&2
  sudo systemctl enable --now unbound || echo "[09] enabling unbound failed" >&2
fi

if [[ "${SHAPING_ENABLE:-true}" == "true" ]]; then
  sudo install -m 0755 /opt/router/render/usr/local/sbin/ul_shaping.sh /usr/local/sbin/ul_shaping.sh || echo "[09] shaping helper install failed" >&2
  /usr/local/sbin/ul_shaping.sh "${ROUTER_WAN_IF:-wan0}" "${SHAPING_EGRESS_KBIT:-0}" "${SHAPING_INGRESS_KBIT:-0}" || echo "[09] shaping helper returned non-zero" >&2
fi

# install ultralight health helper
if [[ -f /opt/router/render/usr/local/sbin/ul_health.sh ]]; then
  sudo install -m 0755 /opt/router/render/usr/local/sbin/ul_health.sh /usr/local/sbin/ul_health.sh || echo "[09] ul_health install failed" >&2
fi

# Air-gapped SPA install if pre-staged in render
if [[ -d /opt/router/render/opt/spa ]]; then
  echo "[09] Found pre-staged SPA artifacts; verifying token and hashes..."
  sudo mkdir -p /opt/spa
  [[ -f /opt/router/render/opt/spa/home-secnet-spa-pq ]] && sudo install -m 0755 /opt/router/render/opt/spa/home-secnet-spa-pq /usr/local/bin/home-secnet-spa-pq
  [[ -f /opt/router/render/opt/spa/home-secnet-spa-pq-client ]] && sudo install -m 0755 /opt/router/render/opt/spa/home-secnet-spa-pq-client /usr/local/bin/home-secnet-spa-pq-client
  [[ -f /opt/router/render/opt/spa/token.json ]] && sudo install -m 0644 /opt/router/render/opt/spa/token.json /opt/spa/token.json
  [[ -f /opt/router/render/opt/spa/token.sig ]] && sudo install -m 0644 /opt/router/render/opt/spa/token.sig /opt/spa/token.sig
  [[ -f /opt/router/render/opt/spa/pubkey.gpg ]] && sudo install -m 0644 /opt/router/render/opt/spa/pubkey.gpg /opt/spa/pubkey.gpg
  [[ -f /opt/router/render/opt/spa/cosign.pub ]] && sudo install -m 0644 /opt/router/render/opt/spa/cosign.pub /opt/spa/cosign.pub
  [[ -f /opt/router/render/opt/spa/cosign.bundle ]] && sudo install -m 0644 /opt/router/render/opt/spa/cosign.bundle /opt/spa/cosign.bundle

  verify_ok=1
  if [[ -f /opt/spa/token.json ]]; then
    if [[ -f /opt/spa/token.sig && -f /opt/spa/pubkey.gpg ]] && command -v gpg >/dev/null 2>&1; then
      gpg --import /opt/spa/pubkey.gpg >/dev/null 2>&1 || { echo "[09] GPG import failed" >&2; exit 1; }
      if gpg --verify /opt/spa/token.sig /opt/spa/token.json >/dev/null 2>&1; then verify_ok=0; else echo "[09] GPG verify failed" >&2; exit 1; fi
    elif [[ -f /opt/spa/token.sig && -f /opt/spa/cosign.pub ]] && command -v cosign >/dev/null 2>&1; then
      if COSIGN_EXPERIMENTAL=1 cosign verify-blob --key /opt/spa/cosign.pub --signature /opt/spa/token.sig /opt/spa/token.json >/dev/null 2>&1; then verify_ok=0; else echo "[09] cosign verify failed" >&2; exit 1; fi
    else
      echo "[09] No signature verification material found; proceeding without signature check" >&2
      verify_ok=0
    fi

    if [[ $verify_ok -eq 0 ]]; then
      # Validate SHA256s in token against staged binaries if present
      server_sha="$(jq -r '.server.sha256 // empty' /opt/spa/token.json 2>/dev/null)"
      client_sha="$(jq -r '.client.sha256 // empty' /opt/spa/token.json 2>/dev/null)"
      if [[ -n "$server_sha" && -x /usr/local/bin/home-secnet-spa-pq ]]; then
        calc_srv="$(sha256sum /usr/local/bin/home-secnet-spa-pq | awk '{print $1}')"
        [[ "$calc_srv" == "$server_sha" ]] || { echo "[09] server sha256 mismatch" >&2; exit 1; }
      fi
      if [[ -n "$client_sha" && -x /usr/local/bin/home-secnet-spa-pq-client ]]; then
        calc_cli="$(sha256sum /usr/local/bin/home-secnet-spa-pq-client | awk '{print $1}')"
        [[ "$calc_cli" == "$client_sha" ]] || { echo "[09] client sha256 mismatch" >&2; exit 1; }
      fi
    fi
  fi
fi

if systemctl is-enabled --quiet suricata 2>/dev/null; then
  sudo systemctl disable --now suricata || echo "[09] disabling suricata failed" >&2
fi

if [[ "${LOG_VERBOSITY:-normal}" == "minimal" ]]; then
  sudo sed -i 's/^#*ForwardToSyslog=.*/ForwardToSyslog=no/g' /etc/systemd/journald.conf || true
  sudo sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=200M/g' /etc/systemd/journald.conf || true
  sudo systemctl restart systemd-journald || true
fi
fi

# Harden login.defs minimally (UMASK and PASS policy)
sudo bash -lc 'cfg=/etc/login.defs; \
  sed -i -E "s/^#?UMASK\s+.*/UMASK\t027/" "$cfg" || echo "UMASK\t027" >> "$cfg"; \
  sed -i -E "s/^#?PASS_MAX_DAYS\s+.*/PASS_MAX_DAYS\t365/" "$cfg" || echo "PASS_MAX_DAYS\t365" >> "$cfg"; \
  sed -i -E "s/^#?PASS_MIN_DAYS\s+.*/PASS_MIN_DAYS\t1/" "$cfg" || echo "PASS_MIN_DAYS\t1" >> "$cfg"; \
  sed -i -E "s/^#?PASS_WARN_AGE\s+.*/PASS_WARN_AGE\t14/" "$cfg" || echo "PASS_WARN_AGE\t14" >> "$cfg";'

# RSyslog forwarding (optional)
if [[ "${RSYSLOG_FORWARD_ENABLE}" == "true" && -n "${RSYSLOG_REMOTE}" ]]; then
  sudo mkdir -p /etc/rsyslog.d
  if [[ -f /opt/router/systemd/security/rsyslog-forward.conf ]]; then
    sudo sed "s#RSYSLOG_REMOTE#${RSYSLOG_REMOTE}#g" /opt/router/systemd/security/rsyslog-forward.conf | sudo tee /etc/rsyslog.d/99-winder-forward.conf >/dev/null
    sudo systemctl restart rsyslog
  fi
fi
EOSSH

echo "[09] Push and apply complete."
