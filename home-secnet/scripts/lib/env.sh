#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

ensure_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$ROOT_DIR/.env.example" ]]; then
      cp "$ROOT_DIR/.env.example" "$ENV_FILE"
      echo "[env] Created .env from .env.example"
    else
      echo "[env] Missing .env and .env.example" >&2
      exit 1
    fi
  fi
}

write_env() {
  local key="$1"; shift
  local val="$1"; shift || true
  local qval="$val"
  # Quote if contains spaces or special chars
  if [[ "$qval" =~ [[:space:]] ]]; then
    qval="\"$qval\""
  fi
  if grep -qE "^${key}=" "$ENV_FILE"; then
    awk -v k="$key" -v v="$qval" 'BEGIN{FS=OFS="="} $1==k {$0=k"="v} {print}' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    echo "${key}=${qval}" >> "$ENV_FILE"
  fi
}

read_default() {
  local prompt="$1"; shift
  local def="$1"; shift
  local out
  read -r -p "$prompt [$def]: " out || true
  if [[ -z "${out}" ]]; then echo "$def"; else echo "$out"; fi
}

ensure_env() {
  local key="$1"; shift
  local prompt="$1"; shift
  local def="${1:-}"; shift || true
  local pattern="${1:-}"; shift || true
  local current="${!key-}"
  if [[ -z "${current:-}" || "$current" == "\"\"" || "$current" == "AAAA... yourkey" || "$current" == "<unset>" ]]; then
    local val
    while true; do
      val=$(read_default "$prompt" "$def")
      if [[ -z "$pattern" || "$val" =~ $pattern ]]; then
        break
      else
        echo "[env] Value does not match expected format: $pattern"
      fi
    done
    write_env "$key" "$val"
    export "$key"="$val"
  fi
}

ensure_choice() {
  local key="$1"; shift
  local prompt="$1"; shift
  local def="$1"; shift
  local choices="$1"; shift
  local current="${!key-}"
  if [[ -z "${current:-}" ]]; then
    local val
    while true; do
      val=$(read_default "$prompt ($choices)" "$def")
      case ",$choices," in *",$val,"*) break;; *) echo "[env] Choose one of: $choices";; esac
    done
    write_env "$key" "$val"
    export "$key"="$val"
  fi
}

random_high_port() {
  shuf -i 49152-65535 -n 1
}

load_env() {
  ensure_env_file
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

