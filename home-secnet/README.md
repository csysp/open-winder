home-secnet

Turn‑key automation for a Proxmox‑based, zero‑trust, WireGuard‑first home network. It provisions an Ubuntu Router VM with nftables, WireGuard, AdGuard Home or Unbound, ISC DHCP, Suricata (inline), and traffic shaping; an optional Logging VM; per‑VLAN DHCP with deny‑by‑default east‑west; and a Proxmox UI reachable only over WireGuard.

Quick Start (Runbook)
- Preflight (tools & distro check): `bash scripts/preflight.sh`
- Prepare environment (.env wizard): `bash scripts/setup_env.sh`
- Detect NICs (confirm/override): `bash scripts/detect_nics.sh`
- Harden Proxmox node: `bash scripts/harden_host.sh`
- Create bridges: `bash scripts/configure_bridges.sh`
- Fetch cloud image: `bash scripts/prepare_cloud_image.sh`
- Create Router VM: `bash scripts/create_router_vm.sh`
- Create Logging VM: `bash scripts/create_logging_vm.sh`
- Render router configs: `bash scripts/render_router_configs.sh`
- Push/apply configs: `bash scripts/apply_router_configs.sh` (prompts for `ROUTER_IP` if needed)
- Lock down node firewall: `bash scripts/apply_node_firewall.sh`
- Security maintenance (updates + scanners): `bash scripts/setup_security_maintenance.sh`
- Verify basic health: `bash scripts/verify_deploy.sh`
- Migrate to flat LAN (optional): `bash scripts/migrate_to_flat_lan.sh`

Make Targets
- `make all`: Runs the end‑to‑end flow above.
- `make router`: Bridges, image, router VM, render, push.
- `make checks`: Runs the basic verifiers.

Assumptions & Prereqs
- Proxmox VE installed on a small host. A second NIC is strongly recommended (USB 3.0 gigabit works well) to separate WAN and LAN.
- Router VM: Ubuntu 24.04 (cloud image) with nftables, WireGuard, AdGuard Home or Unbound, ISC DHCP, Suricata, and tc.
- VLANs optional. Set `USE_VLANS=true` for segmented LANs; the default is a flat LAN for unmanaged switches.
- Proxmox UI (`:8006`) is only reachable from the WireGuard subnet.

Network Models
- Two‑NIC recommended: `vmbr0` for WAN, `vmbr1` for LAN/VLAN trunk.
- One‑NIC fallback: WAN on `vmbr0`. Separate LAN is not possible without a second NIC; scripts warn and let you abort.

WireGuard Access
- Server keys are generated during render in `render/wg/`.
- Router config is applied to `/etc/wireguard/wg0.conf`.
- A sample client is created at `clients/wg-client1.conf`; set `Endpoint = <YOUR_PUB_IP>:${WG_PORT}` before use.
- Optional QUIC wrapper: set `WRAP_MODE=hysteria2` to run Hysteria2 on UDP `${WRAP_LISTEN_PORT}` and forward to WireGuard. A sample `clients/hysteria2-client.yaml` is generated.
- Optional SPA (Single Packet Authorization): set `SPA_ENABLE=true` to require an SPA knock before the WireGuard port is allowed; see SPA variables in `.env`.

Double‑Hop Egress (Optional)
- Enable with `DOUBLE_HOP_ENABLE=true` and fill `WG2_*` in `.env`. This creates `/etc/wireguard/wg1.conf` on the router and policy routes WG client traffic out via the remote exit node. Configure the exit node to accept `${WG2_ADDRESS}` and allow forwarding/NAT.

DNS Options
- Default: AdGuard Home with encrypted upstreams and DNSSEC, serving LAN and WG on port 53.
- Alternative: set `DNS_STACK=unbound` in `.env`, re‑render, and push for local validating recursion.
- To offer DoH/DoQ directly to clients via AdGuard Home, configure a trusted certificate and enable HTTPS listeners.

Suricata & Logging
- Suricata is configured inline on VLAN subinterfaces. Tune with `suricata-update` on the Router VM.
- EVE JSON logs at `/var/log/suricata/eve.json`; forward via rsyslog to the Logging VM if desired.

Proxmox Firewall
- Node firewall rules are rendered from `.env` and installed during the flow.
- Default inbound DROP; SSH allowed from TRUSTED; `:8006` allowed only from WG and localhost.

Security Highlights
- SSH key‑only access; local passwords disabled where possible.
- nftables default‑drop with inter‑VLAN isolation.
- DHCP/DNS bound to VLANs and WG only.
- Daily maintenance: unattended‑upgrades, Lynis audit, rkhunter/chkrootkit, and ClamAV on host and router.
- Alerts: emails to `ALERT_EMAIL` on update errors, reboot‑required, audit warnings, or detections. Optional SMTP relay via msmtp (`SMTP_ENABLE=true`).

Traffic Shaping
- fq_codel enabled on LAN. Basic rate limiting is supported; more advanced padding/morphing may be added later.

Next Steps
- Connect a peer using `clients/wg-client1.conf` (or generate a QR with `qrencode`).
- Move LAN devices to the correct VLAN ports on your switch.
- Optionally route Proxmox updates through the Router VM’s WireGuard egress.

Notes & Limitations
- Some downloads (e.g., images) are best‑effort and may require retries.
- Static WAN: adjust the rendered netplan or extend the render step to write static WAN from `.env`.
- Email alerts require a mailer. Scripts prefer `mail` (bsd‑mailx), then `msmtp`, then `sendmail`. Set SMTP vars in `.env` to relay.

Migration
- If you started with VLANs and want a flat LAN:
  - Run `bash scripts/migrate_to_flat_lan.sh` on the Proxmox host to update bridges, remove VM NIC VLAN tags (Logging VM), regenerate configs, and push to the Router VM. Router configs are backed up before replacement.
  - The Router VM LAN interface remains `${ROUTER_LAN_IF}` with IP `${GW_TRUSTED}`; VLAN subinterfaces are removed by netplan.
  - DHCP will listen only on `${ROUTER_LAN_IF}`.
