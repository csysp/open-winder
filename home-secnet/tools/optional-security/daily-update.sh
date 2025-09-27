#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/home-secnet
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/daily-update.log"
date >> "$LOGFILE"
err=0
apt-get update -y >> "$LOGFILE" 2>&1 || err=1
if command -v unattended-upgrade >/dev/null 2>&1; then
  unattended-upgrade -d >> "$LOGFILE" 2>&1 || true
else
  DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade >> "$LOGFILE" 2>&1 || err=1
fi
apt-get autoremove -y >> "$LOGFILE" 2>&1 || true
apt-get autoclean -y >> "$LOGFILE" 2>&1 || true
echo "-- done --" >> "$LOGFILE"

# Alert conditions: errors or reboot required
ALERT_SH="/opt/router/security/alert-mail.sh"
if [[ -x "$ALERT_SH" ]]; then
  if [[ $err -ne 0 ]] || grep -qiE "(^E:|error|failed)" "$LOGFILE"; then
    "$ALERT_SH" "[home-secnet][router] Apt update errors" "Errors detected during daily update. See $LOGFILE"
  fi
  if [[ -f /var/run/reboot-required ]]; then
    "$ALERT_SH" "[home-secnet][router] Reboot required" "A reboot is required after updates."
  fi
fi
