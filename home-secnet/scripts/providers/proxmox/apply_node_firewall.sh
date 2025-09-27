#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/apply_node_firewall.sh"

