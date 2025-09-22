#!/usr/bin/env bash
set -euo pipefail

echo "[09] Pushing configs into Router VM and applying..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

# Determine Router VM IP via QEMU agent (expects DHCP on WAN or console access)
ROUTER_IP="${ROUTER_IP:-}" # allow override
if [[ -z "${ROUTER_IP}" ]]; then
  if qm agent $ROUTER_VM_ID network-get-interfaces >/dev/null 2>&1; then
    ROUTER_IP=$(qm agent $ROUTER_VM_ID network-get-interfaces | awk -F'"' '/"ip-address":/ {print $4}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1 || true)
  fi
fi
if [[ -z "${ROUTER_IP}" ]]; then
  read -r -p "[09] Router VM IP not detected. Enter Router IP: " ROUTER_IP
  if [[ -z "$ROUTER_IP" ]]; then echo "[09] Router IP is required." >&2; exit 1; fi
fi

echo "[09] Using Router VM IP: $ROUTER_IP"

RUSER=${ROUTER_ADMIN_USER}

ssh -o StrictHostKeyChecking=no ${RUSER}@${ROUTER_IP} "sudo mkdir -p /opt/router && sudo chown \$(id -un):\$(id -gn) /opt/router"
rsync -av --delete "$ROOT_DIR/render/router/configs/" ${RUSER}@${ROUTER_IP}:/opt/router/
rsync -av "$ROOT_DIR/router/systemd/" ${RUSER}@${ROUTER_IP}:/opt/router/systemd/
rsync -av "$ROOT_DIR/router/hardening/" ${RUSER}@${ROUTER_IP}:/opt/router/hardening/
rsync -av "$ROOT_DIR/router/cloudinit/" ${RUSER}@${ROUTER_IP}:/opt/router/cloudinit/

ssh ${RUSER}@${ROUTER_IP} "USE_VLANS='${USE_VLANS}' ROUTER_LAN_IF='${ROUTER_LAN_IF}' VLAN_TRUSTED='${VLAN_TRUSTED}' VLAN_IOT='${VLAN_IOT}' VLAN_GUEST='${VLAN_GUEST}' VLAN_LAB='${VLAN_LAB}' DISABLE_USB_STORAGE='${DISABLE_USB_STORAGE}' HARDEN_AUDITD='${HARDEN_AUDITD}' INSTALL_AIDE='${INSTALL_AIDE}' FAIL2BAN_ENABLE='${FAIL2BAN_ENABLE}' ADGUARD_VERSION='${ADGUARD_VERSION}' HYSTERIA_VERSION='latest' bash -s" <<'EOSSH'
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
rm -f /etc/rsyslog.d/90-remote.conf 2>/dev/null || true

# Install daily security maintenance timers
sudo install -d -m 0755 /opt/router/security
sudo cp -a /opt/router/systemd/security/*.sh /opt/router/security/
sudo chmod +x /opt/router/security/*.sh
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
  sudo systemctl disable --now unbound 2>/dev/null || true
  sudo systemctl enable --now adguardhome.service
else
  echo "[router] DNS stack: Unbound"
  sudo systemctl enable --now unbound
  sudo systemctl disable --now adguardhome.service 2>/dev/null || true
fi

# Start QUIC wrapper if configured
if [[ -f /etc/hysteria/config.yaml ]]; then
  if [[ ! -x /opt/hysteria/hysteria ]]; then
    sudo HYSTERIA_VERSION=latest /opt/hysteria/install-hysteria.sh
  fi
  # Generate self-signed cert if missing
  if [[ ! -f /etc/hysteria/server.crt || ! -f /etc/hysteria/server.key ]]; then
    sudo apt-get update -y && sudo apt-get install -y openssl || true
    sudo openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=${WRAP_DOMAIN:-hysteria.local}" -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt
    sudo chmod 600 /etc/hysteria/server.key
  fi
  sudo systemctl enable --now hysteria.service
fi

# Configure SPA gating if enabled (only when access.conf is present)
if [[ -f /opt/router/access.conf ]]; then
  sudo install -m 0755 /opt/router/systemd/fwknop/fwknop-add.sh /opt/router/fwknop-add.sh
  sudo apt-get update -y && sudo apt-get install -y fwknop-server || true
  sudo mkdir -p /etc/fwknopd
  sudo cp /opt/router/fwknopd.conf /etc/fwknopd/fwknopd.conf
  sudo cp /opt/router/access.conf /etc/fwknopd/access.conf
  sudo systemctl enable --now fwknopd
fi

sudo netplan apply || true
sudo nft -f /etc/nftables.conf || true
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
sudo systemctl enable --now suricata || true

# Apply hardening: sysctl, modprobe blacklist, ssh, login defs, banner, profile
sudo mkdir -p /etc/sysctl.d /etc/modprobe.d /etc/security/limits.d /etc/profile.d /etc/home-secnet
sudo cp /opt/router/hardening/sysctl.conf /etc/sysctl.d/99-home-secnet.conf
sudo cp /opt/router/hardening/modprobe-blacklist.conf /etc/modprobe.d/blacklist-home-secnet.conf
sudo cp /opt/router/hardening/profile.d-home-secnet.sh /etc/profile.d/99-home-secnet.sh
sudo cp /opt/router/hardening/issue /etc/issue
sudo cp /opt/router/hardening/issue /etc/issue.net
sudo sysctl --system || true
# Optional disable usb-storage
if [[ "${DISABLE_USB_STORAGE}" == "true" ]]; then
  echo 'install usb-storage /bin/false' | sudo tee -a /etc/modprobe.d/blacklist-home-secnet.conf >/dev/null
fi
# SSH hardening
ROUTER_ADMIN_USER="$ROUTER_ADMIN_USER" bash /opt/router/hardening/sshd_hardening.sh || true

# Install recommended packages
sudo apt-get update -y
sudo apt-get install -y libpam-tmpdir libpam-pwquality lynis rkhunter chkrootkit clamav-daemon clamav-freshclam
sudo systemctl enable --now clamav-freshclam || true
if [[ "${HARDEN_AUDITD}" == "true" ]]; then
  sudo apt-get install -y auditd audispd-plugins
  sudo systemctl enable --now auditd || true
fi
if [[ "${INSTALL_AIDE}" == "true" ]]; then
  sudo apt-get install -y aide
  sudo aideinit || true
fi
if [[ "${FAIL2BAN_ENABLE}" == "true" ]]; then
  sudo apt-get install -y fail2ban
  echo -e "[sshd]\nenabled = true\nmaxretry = 3\nbantime = 1h" | sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null
  sudo systemctl enable --now fail2ban || true
fi

# Harden login.defs minimally (UMASK and PASS policy)
sudo bash -lc 'cfg=/etc/login.defs; \
  sed -i -E "s/^#?UMASK\s+.*/UMASK\t027/" "$cfg" || echo "UMASK\t027" >> "$cfg"; \
  sed -i -E "s/^#?PASS_MAX_DAYS\s+.*/PASS_MAX_DAYS\t365/" "$cfg" || echo "PASS_MAX_DAYS\t365" >> "$cfg"; \
  sed -i -E "s/^#?PASS_MIN_DAYS\s+.*/PASS_MIN_DAYS\t1/" "$cfg" || echo "PASS_MIN_DAYS\t1" >> "$cfg"; \
  sed -i -E "s/^#?PASS_WARN_AGE\s+.*/PASS_WARN_AGE\t14/" "$cfg" || echo "PASS_WARN_AGE\t14" >> "$cfg";'
EOSSH

echo "[09] Push and apply complete."
