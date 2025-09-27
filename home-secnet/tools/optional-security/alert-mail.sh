#!/usr/bin/env bash
set -euo pipefail

SUBJECT="$1"; shift || true
BODY="$1"; shift || true

ALERT_CONF="/etc/home-secnet/alert.conf"
MAIL_TO="${ALERT_EMAIL:-}"
if [[ -f "$ALERT_CONF" ]]; then
  # shellcheck disable=SC1090
  source "$ALERT_CONF"
fi

if [[ -z "${MAIL_TO:-}" ]]; then
  echo "[alert] ALERT_EMAIL not configured; skipping email: $SUBJECT" >&2
  exit 0
fi

send_mail() {
  local subject="$1"; shift
  local body="$1"; shift
  if command -v mail >/dev/null 2>&1; then
    printf "%s\n" "$body" | mail -s "$subject" "$MAIL_TO" || true
    return 0
  fi
  if command -v msmtp >/dev/null 2>&1; then
    printf "Subject: %s\nTo: %s\n\n%s\n" "$subject" "$MAIL_TO" "$body" | msmtp -t || true
    return 0
  fi
  if command -v sendmail >/dev/null 2>&1; then
    printf "Subject: %s\nTo: %s\n\n%s\n" "$subject" "$MAIL_TO" "$body" | sendmail -t || true
    return 0
  fi
  echo "[alert] No mailer available (mail/msmtp/sendmail)." >&2
}

send_mail "$SUBJECT" "$BODY"

