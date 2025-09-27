#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Delegate to original script for now
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/configure_bridges.sh"

