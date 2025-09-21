#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/.env"
if [[ "${USE_VLANS:-false}" == "true" ]]; then
  echo "Manual: attempt to ping across VLANs should fail by design."
  echo "From TRUSTED, ping a host in IOT/GUEST/LAB and confirm failure."
else
  echo "VLAN isolation check not applicable (USE_VLANS=false)."
fi
