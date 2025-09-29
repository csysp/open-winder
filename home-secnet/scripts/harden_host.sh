#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'
# Purpose: Apply baseline hardening to Proxmox host.
# Inputs: VERBOSE (optional)
# Outputs: none
# Side effects: Modifies system configs (ssh, fail2ban, kernel params)

usage() {
  cat <<'USAGE'
Usage: harden_host.sh
  Applies baseline hardening measures on the host.

Environment:
  VERBOSE=1   Enable verbose logging
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage; exit 0
fi
# shellcheck source=scripts/lib/log.sh
# shellcheck source=home-secnet/scripts/lib/log.sh
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/log.sh"
if [[ -f "$LIB_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$LIB_PATH"
fi

log_info "[03] Hardening Proxmox host..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/env.sh"
set -a; load_env; set +a
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "[03] Run as root on the Proxmox host." >&2
  exit 1
fi

echo "[03] Enforcing SSH key-only, disabling root password login and hardening sshd..."
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
# Conservative ssh hardening
sed -i -E 's/^#?X11Forwarding .*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i -E 's/^#?AllowAgentForwarding .*/AllowAgentForwarding no/' /etc/ssh/sshd_config
sed -i -E 's/^#?AllowTcpForwarding .*/AllowTcpForwarding no/' /etc/ssh/sshd_config
sed -i -E 's/^#?TCPKeepAlive .*/TCPKeepAlive no/' /etc/ssh/sshd_config
sed -i -E 's/^#?ClientAliveInterval .*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i -E 's/^#?ClientAliveCountMax .*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
sed -i -E 's/^#?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i -E 's/^#?MaxSessions .*/MaxSessions 2/' /etc/ssh/sshd_config
sed -i -E 's/^#?LogLevel .*/LogLevel VERBOSE/' /etc/ssh/sshd_config
sed -i -E 's/^#?UseDNS .*/UseDNS no/' /etc/ssh/sshd_config
if ! grep -q '^AllowUsers ' /etc/ssh/sshd_config; then
  echo "AllowUsers ${ROUTER_ADMIN_USER:-admin} ${LOG_ADMIN_USER:-admin}" >> /etc/ssh/sshd_config
fi
systemctl reload ssh || systemctl reload sshd || log_warn "[03] ssh reload failed; check sshd_config"

echo "[03] Installing lynis and security tooling..."
apt-get update -y
apt-get install -y lynis libpam-tmpdir libpam-pwquality fail2ban
systemctl enable --now fail2ban || log_warn "[03] fail2ban enable/start failed"

# Ensure fail2ban monitors sshd via systemd journal
if [[ ! -f /etc/fail2ban/jail.local ]]; then
  cp -f /etc/fail2ban/jail.conf /etc/fail2ban/jail.local || log_warn "[03] could not copy fail2ban jail.local"
fi
mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
EOF
systemctl restart fail2ban || log_warn "[03] fail2ban restart failed"

lynis audit system || log_warn "[03] lynis audit returned non-zero"

echo "[03] Enabling Proxmox node firewall with inbound DROP..."
pve-firewall status || log_warn "[03] pve-firewall status failed"
if command -v pvesh >/dev/null 2>&1; then
  # Enable cluster and node firewall, set default policies
  pvesh set "/cluster/firewall/options" --enable 1 >/dev/null 2>&1 || log_warn "[03] Could not enable cluster firewall options"
  pvesh set "/nodes/$(hostname)/firewall/options" --enable 1 --policy_in DROP --policy_out ACCEPT >/dev/null 2>&1 || log_warn "[03] Could not enable node firewall or set policies"
fi
# Apply firewall rules
pve-firewall compile || log_warn "[03] pve-firewall compile failed"
pve-firewall restart || log_warn "[03] pve-firewall restart failed"

echo "[03] Disabling unused services (nfs, samba/cifs if present)..."
systemctl disable --now nfs-server 2>/dev/null || log_warn "[03] could not disable nfs-server"
systemctl disable --now smbd nmbd 2>/dev/null || log_warn "[03] could not disable smbd/nmbd"

echo "[03] Applying kernel/network hardening sysctls..."
cat > /etc/sysctl.d/99-home-secnet.conf <<'EOF'
fs.suid_dumpable = 0
fs.protected_fifos = 2
fs.protected_regular = 2
kernel.kptr_restrict = 2
kernel.perf_event_paranoid = 3
kernel.sysrq = 0
kernel.yama.ptrace_scope = 1
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF
sysctl --system || log_warn "[03] sysctl --system returned non-zero"

echo "[03] Blacklisting uncommon network protocols..."
cat > /etc/modprobe.d/blacklist-home-secnet.conf <<'EOF'
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
EOF

echo "[03] Setting login banner and secure umask..."
echo "Authorized access only. Disconnect immediately if you are not authorized." > /etc/issue
cp /etc/issue /etc/issue.net
if ! grep -q '^UMASK' /etc/login.defs; then echo 'UMASK 027' >> /etc/login.defs; fi
echo 'export TMOUT=900; readonly TMOUT; umask 027' > /etc/profile.d/99-home-secnet.sh

echo "[03] Done basic hardening. Detailed rules applied in step 10."
