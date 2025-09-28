#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Ensure no generated artifacts land under router/ after render.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

changed=$(git status --porcelain=1 -- router | wc -l | tr -d ' ')
if [[ "$changed" != "0" ]]; then
  echo "[verify] router/ contains modified/untracked files; generated output must not write here." >&2
  git status --porcelain=1 -- router >&2 || true
  exit 1
fi
echo "[verify] router/ is clean (no generated artifacts)."

