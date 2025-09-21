#!/usr/bin/env bash
set -euo pipefail

echo "[11] Setting up daily updates and security scans (host + VMs)..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"

if [[ $EUID -ne 0 ]]; then
  echo "[11] Run as root on the Proxmox host." >&2
  exit 1
fi

setup_unattended() {
  echo "[11] Installing unattended-upgrades and configuring apt periodic..."
  apt-get update -y
  apt-get install -y unattended-upgrades apt-listchanges
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
}

setup_host_security_units() {
  echo "[11] Installing host scanners (lynis, rkhunter, chkrootkit, clamav)..."
  apt-get install -y lynis rkhunter chkrootkit clamav-daemon clamav-freshclam msmtp bsd-mailx
  systemctl enable --now clamav-freshclam || true

  mkdir -p /usr/local/sbin
  cat > /usr/local/sbin/hsn-daily-update.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/home-secnet
mkdir -p "$LOGDIR"
date >> "$LOGDIR/host-daily-update.log"
apt-get update -y >> "$LOGDIR/host-daily-update.log" 2>&1 || true
unattended-upgrade -d >> "$LOGDIR/host-daily-update.log" 2>&1 || true
apt-get autoremove -y >> "$LOGDIR/host-daily-update.log" 2>&1 || true
apt-get autoclean -y >> "$LOGDIR/host-daily-update.log" 2>&1 || true
EOS
  chmod +x /usr/local/sbin/hsn-daily-update.sh

  cat > /usr/local/sbin/hsn-daily-lynis.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/lynis
mkdir -p "$LOGDIR"
lynis audit system --quick --auditor "home-secnet" --logfile "$LOGDIR/host-lynis.log" || true
EOS
  chmod +x /usr/local/sbin/hsn-daily-lynis.sh

  cat > /usr/local/sbin/hsn-daily-rootkit.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/home-secnet
mkdir -p "$LOGDIR"
rkhunter --update || true
rkhunter --propupd || true
rkhunter --check --sk >> "$LOGDIR/host-rkhunter.log" 2>&1 || true
chkrootkit >> "$LOGDIR/host-chkrootkit.log" 2>&1 || true
EOS
  chmod +x /usr/local/sbin/hsn-daily-rootkit.sh

  cat > /usr/local/sbin/hsn-daily-malware.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/clamav
mkdir -p "$LOGDIR"
freshclam || true
clamscan -r --infected --log="$LOGDIR/host-scan.log" /etc /bin /sbin /usr /var /opt || true
EOS
  chmod +x /usr/local/sbin/hsn-daily-malware.sh

  cat > /etc/systemd/system/hsn-daily-update.service <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Update

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hsn-daily-update.sh
Nice=10
IOSchedulingClass=idle
EOS
  cat > /etc/systemd/system/hsn-daily-update.timer <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Update Timer

[Timer]
OnCalendar=01:30
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOS

  cat > /etc/systemd/system/hsn-daily-lynis.service <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Lynis Audit

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hsn-daily-lynis.sh
Nice=10
IOSchedulingClass=idle
EOS
  cat > /etc/systemd/system/hsn-daily-lynis.timer <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Lynis Timer

[Timer]
OnCalendar=03:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOS

  cat > /etc/systemd/system/hsn-daily-rootkit.service <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Rootkit Scan

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hsn-daily-rootkit.sh
Nice=10
IOSchedulingClass=idle
EOS
  cat > /etc/systemd/system/hsn-daily-rootkit.timer <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Rootkit Timer

[Timer]
OnCalendar=04:30
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOS

  cat > /etc/systemd/system/hsn-daily-malware.service <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Malware Scan

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hsn-daily-malware.sh
Nice=10
IOSchedulingClass=idle
EOS
  cat > /etc/systemd/system/hsn-daily-malware.timer <<'EOS'
[Unit]
Description=Home-SecNet Host Daily Malware Timer

[Timer]
OnCalendar=02:45
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOS

  systemctl daemon-reload
  systemctl enable --now hsn-daily-update.timer hsn-daily-lynis.timer hsn-daily-rootkit.timer hsn-daily-malware.timer
}

setup_rsyslog_forward() {
  if [[ -n "${LOG_VM_IP:-}" ]]; then
    echo "[11] Configuring host rsyslog forwarding to ${LOG_VM_IP}:514"
    echo "*.* @@${LOG_VM_IP}:514" > /etc/rsyslog.d/90-remote.conf
    systemctl restart rsyslog || true
  fi
}

echo "[11] Writing alert email config for host"
mkdir -p /etc/home-secnet
echo "ALERT_EMAIL=${ALERT_EMAIL}" > /etc/home-secnet/alert.conf

if [[ "${SMTP_ENABLE}" == "true" && -n "${SMTP_HOST}" ]]; then
  echo "[11] Configuring msmtp for host SMTP relay"
  cat > /etc/msmtprc <<CONF
defaults
auth           on
tls            ${SMTP_TLS}
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account default
host ${SMTP_HOST}
port ${SMTP_PORT}
user ${SMTP_USER}
password ${SMTP_PASSWORD}
from ${SMTP_USER}
syslog on
CONF
  chmod 600 /etc/msmtprc
fi

setup_unattended
setup_host_security_units
setup_rsyslog_forward

echo "[11] Host daily maintenance configured."

# Configure Router VM packages for maintenance
ROUTER_IP="${ROUTER_IP:-}"
if [[ -z "$ROUTER_IP" ]]; then
  echo "[11] Router IP not set; if you want to install packages on Router now, export ROUTER_IP and re-run." || true
  exit 0
fi

echo "[11] Installing packages and enabling timers on Router VM ($ROUTER_IP)..."
ssh -o StrictHostKeyChecking=no ${ROUTER_ADMIN_USER}@${ROUTER_IP} bash -s <<'EOSSH'
set -euo pipefail
sudo apt-get update -y
sudo apt-get install -y unattended-upgrades apt-listchanges lynis rkhunter chkrootkit clamav-daemon clamav-freshclam msmtp bsd-mailx
sudo systemctl enable --now clamav-freshclam || true
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now home-secnet-daily-update.timer home-secnet-daily-lynis.timer home-secnet-daily-rootkit.timer home-secnet-daily-malware.timer || true
EOSSH

echo "[11] Router maintenance configured. Consider running similar on the Logging VM if desired."
