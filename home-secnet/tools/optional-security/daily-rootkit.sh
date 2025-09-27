#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/home-secnet
mkdir -p "$LOGDIR"
RKLOG="$LOGDIR/rkhunter.log"
CKLOG="$LOGDIR/chkrootkit.log"
if command -v rkhunter >/dev/null 2>&1; then
  if ! rkhunter --update; then echo "[router][rkhunter] update failed" >> "$RKLOG"; fi
  if ! rkhunter --propupd; then echo "[router][rkhunter] propupd failed" >> "$RKLOG"; fi
  if ! rkhunter --check --sk >> "$RKLOG" 2>&1; then echo "[router][rkhunter] check failed" >> "$RKLOG"; fi
fi
if command -v chkrootkit >/dev/null 2>&1; then
  if ! chkrootkit >> "$CKLOG" 2>&1; then echo "[router][chkrootkit] failed" >> "$CKLOG"; fi
fi

ALERT_SH="/opt/router/security/alert-mail.sh"
if [[ -x "$ALERT_SH" ]]; then
  if [[ -f "$RKLOG" ]] && grep -qiE "warning|suspect|infected" "$RKLOG"; then
    "$ALERT_SH" "[home-secnet][router] RKHunter warnings" "Check $RKLOG"
  fi
  if [[ -f "$CKLOG" ]] && grep -qiE "INFECTED|Vulnerable" "$CKLOG"; then
    "$ALERT_SH" "[home-secnet][router] chkrootkit findings" "Check $CKLOG"
  fi
fi
