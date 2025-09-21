#!/usr/bin/env bash
set -euo pipefail
CFG=/etc/ssh/sshd_config
sudo sed -i -E 's/^#?Port .*/Port 22/' "$CFG"
sudo sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' "$CFG"
sudo sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin no/' "$CFG"
sudo sed -i -E 's/^#?X11Forwarding .*/X11Forwarding no/' "$CFG"
sudo sed -i -E 's/^#?AllowAgentForwarding .*/AllowAgentForwarding no/' "$CFG"
sudo sed -i -E 's/^#?AllowTcpForwarding .*/AllowTcpForwarding no/' "$CFG"
sudo sed -i -E 's/^#?TCPKeepAlive .*/TCPKeepAlive no/' "$CFG"
sudo sed -i -E 's/^#?ClientAliveInterval .*/ClientAliveInterval 300/' "$CFG"
sudo sed -i -E 's/^#?ClientAliveCountMax .*/ClientAliveCountMax 2/' "$CFG"
sudo sed -i -E 's/^#?MaxAuthTries .*/MaxAuthTries 3/' "$CFG"
sudo sed -i -E 's/^#?MaxSessions .*/MaxSessions 2/' "$CFG"
sudo sed -i -E 's/^#?LogLevel .*/LogLevel VERBOSE/' "$CFG"
sudo sed -i -E 's/^#?UseDNS .*/UseDNS no/' "$CFG"
# Optional AllowUsers if provided
if [[ -n "${ROUTER_ADMIN_USER:-}" ]]; then
  if ! grep -qE '^AllowUsers ' "$CFG"; then
    echo "AllowUsers ${ROUTER_ADMIN_USER}" | sudo tee -a "$CFG" >/dev/null
  fi
fi
sudo systemctl reload ssh || sudo systemctl reload sshd || true
