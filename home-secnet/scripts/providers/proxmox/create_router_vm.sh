#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/create_router_vm.sh"

