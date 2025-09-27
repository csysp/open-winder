#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/lynis
mkdir -p "$LOGDIR"
OUT="$LOGDIR/lynis.log"
if ! lynis audit system --quick --auditor "home-secnet" --logfile "$OUT"; then
  echo "[router][lynis] audit failed" >> "$OUT"
fi

ALERT_SH="/opt/router/security/alert-mail.sh"
if [[ -x "$ALERT_SH" ]]; then
  if grep -qiE "warning|suggestion" "$OUT"; then
    "$ALERT_SH" "[home-secnet][router] Lynis findings" "Lynis reported warnings/suggestions. See $OUT"
  fi
fi
