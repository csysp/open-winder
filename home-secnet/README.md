home-secnet

Turn-key repo to provision a Proxmox-based, zero-trust, WireGuard-first, VLAN-segmented home network with an Ubuntu Router VM (nftables + WireGuard + Unbound/AdGuard Home + Suricata inline), per-VLAN DHCP, deny-by-default east-west, and Proxmox UI reachable only via WireGuard.

Runbook
- Preflight (tools & distro check): `bash scripts/preflight.sh`
- Prep env (guided prompts): `bash scripts/setup_env.sh`
- Detect NICs (confirm/override): `bash scripts/detect_nics.sh`
- Harden node: `bash scripts/harden_host.sh`
- Bridges: `bash scripts/configure_bridges.sh`
- Cloud image: `bash scripts/prepare_cloud_image.sh`
- Router VM: `bash scripts/create_router_vm.sh`
- Logging VM: `bash scripts/create_logging_vm.sh`
- Render configs: `bash scripts/render_router_configs.sh`
- Push/apply: `bash scripts/apply_router_configs.sh` (prompts for `ROUTER_IP` if needed)
- Lockdown node FW: `bash scripts/apply_node_firewall.sh`
- Security maintenance (updates + scans): `bash scripts/setup_security_maintenance.sh`
- Checks: `bash scripts/verify_deploy.sh`
- Migrate to flat LAN (if coming from VLAN mode): `bash scripts/migrate_to_flat_lan.sh`

Make targets
- `make all`: Steps 2–11.
- `make router`: Bridges, image, router VM, render, push.
- `make checks`: Basic verifiers.

Assumptions
- Proxmox VE installed on a mini-PC. USB NIC recommended for WAN or LAN.
- 1-NIC fallback warns and exits until a second NIC is present.
- Router VM: Ubuntu 24.04 with nftables, wireguard, unbound or AdGuard Home, isc-dhcp-server, suricata, tc.
- VLANs optional: set `USE_VLANS=true` for segmented LANs; default is flat LAN for unmanaged switches.
- Proxmox UI (8006) allowed only from WG subnet.

One-NIC Guidance
- Strongly recommend adding USB 3.0 gigabit NIC.
- Fallback: `vmbr0` WAN only; cannot provide separate LAN without a second NIC. Scripts warn and let you abort.

WireGuard
- Server keys auto-generated in `render/wg/` when rendering configs.
- Router config at `/etc/wireguard/wg0.conf` via step 7.
- A sample client `clients/wg-client1.conf` is created; set `Endpoint = <YOUR_PUB_IP>:${WG_PORT}` before use.
- Optional QUIC/TLS wrapper: set `WRAP_MODE=hysteria2` to run Hysteria2 on UDP `${WRAP_LISTEN_PORT}` and forward to WireGuard. A client sample `clients/hysteria2-client.yaml` is generated; run the client on your device to wrap WG over QUIC.

Double-Hop Egress (Optional)
- Set `DOUBLE_HOP_ENABLE=true` and fill `WG2_*` in `.env` to create `/etc/wireguard/wg1.conf` on the router, connecting to a remote exit node. Policy routing ensures WG client traffic egresses via `wg1`. Configure the exit node to accept `${WG2_ADDRESS}` and allow forwarding/NAT.

DNS
- Default DNS is AdGuard Home with upstream encryption and DNSSEC. AdGuard forwards to DoH upstreams (Quad9 and Cloudflare) and enables DNSSEC checking, and serves DNS to LAN/WG on port 53.
- To use Unbound instead, set `DNS_STACK=unbound` in `.env`, re-render and push. Unbound provides local validation and recursion.
- Optional: To provide DoH/DoQ directly to clients, configure a trusted TLS certificate for AdGuard Home and enable its HTTPS endpoints; clients must trust that certificate. Ask if you want me to wire this with a self-signed or ACME flow.

Suricata
- Configured for inline IPS on VLAN subinterfaces. Tune rules with `suricata-update` on the Router VM.
- EVE JSON logs at `/var/log/suricata/eve.json`. You can forward via rsyslog to the logging VM.

Proxmox Firewall
- Node firewall rules render from `.env` and are installed in step 8.
- Default inbound DROP; allow SSH from TRUSTED; allow 8006 only from WG subnet and localhost.

Security Highlights
- SSH key-only access; passwords disabled.
- nftables default drop; inter-VLAN blocked.
- DHCP/DNS bound per VLAN and WG only.
- Suricata inline on Router VM; logs can be centralized.
- tc shaping to smooth egress bursts.
- Daily maintenance: unattended-upgrades, Lynis audit, rkhunter/chkrootkit, and ClamAV scheduled on host and router.
- Urgent alerts: emails to `ALERT_EMAIL` (default `sam@albertabadlands.com`) on update errors, reboot-required, Lynis warnings, rootkit/malware detections. Optional SMTP relay via msmtp (`SMTP_ENABLE=true` in `.env`).

Traffic Shaping & Padding
- Current: fq_codel on LAN; optional rate limits to be added.
- Future (not implemented): transport padding, morphing, QUIC parameter tuning, dummy packet scheduling.

Next Steps
- Connect a peer using `clients/wg-client1.conf` (or QR with `qrencode`).
- Move LAN devices to correct VLAN ports on your managed switch.
- (Optional) Route Proxmox updates via Router VM’s WireGuard egress.

Notes
- Some operations are best-effort (image fetch) and may require manual tweaks.
- If WAN is static, adjust rendered netplan or teach the render script to write static WAN from `.env`.
- Email alerts require a mailer: scripts prefer `mail` (bsd-mailx), then `msmtp`, then `sendmail`. Set SMTP vars in `.env` to relay via your provider; otherwise local MTA is required.
Migration
- If you initially set up with VLANs and now want a flat LAN:
  - Run `bash scripts/10_migrate_to_flat.sh` as root on the Proxmox host to update bridges, remove VM NIC VLAN tag (Logging VM), regenerate configs, and push to the Router VM. It backs up router configs before replacing.
  - Your Router VM’s LAN interface becomes `${ROUTER_LAN_IF}` with IP `${GW_TRUSTED}`; VLAN subinterfaces are removed by netplan.
  - DHCP will listen on `${ROUTER_LAN_IF}` only.
