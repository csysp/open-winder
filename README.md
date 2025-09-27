Winder (Router System)

Winder provides turn‑key automation for a Proxmox‑based, zero‑trust, WireGuard‑first home network. It provisions an Ubuntu Router VM with nftables, WireGuard, PQ‑KEM SPA control‑plane (default), AdGuard Home or Unbound, ISC DHCP, Suricata (inline), and traffic shaping; per‑VLAN DHCP with deny‑by‑default east‑west; and a Proxmox UI reachable only over WireGuard.

Quick Start (Provider‑Aware)
- Preflight: `bash home-secnet/scripts/preflight.sh`
- Setup env: `bash home-secnet/scripts/setup_env.sh` (select baremetal by default; proxmox optional when detected)
- Host step (provider‑aware): `make -C home-secnet host`
  - Baremetal: previews network changes (use `providers/baremetal/configure_network.sh --apply` to write netplan safely)
  - Proxmox: configures bridges/VM/firewall via adapters
- Render configs: `bash home-secnet/scripts/render_router_configs.sh`
- Apply configs: `bash home-secnet/scripts/apply_router_configs.sh`
- Security maintenance: `bash home-secnet/scripts/setup_security_maintenance.sh`
- Verify health: `bash home-secnet/scripts/verify_deploy.sh`

Pre-Alpha / Pre-Release
This project is pre‑alpha. Expect rapid iteration and breaking changes. While releases are paused, install from main with the one‑liner installer: `curl -fsSL https://raw.githubusercontent.com/csysp/winder/main/home-secnet/scripts/install_winder.sh -o /tmp/install_winder.sh && chmod +x /tmp/install_winder.sh && /tmp/install_winder.sh`.

Make Targets
- `make all`: Runs the end-to-end flow above.
- `make router`: Bridges, image, router VM, render, push.
- `make checks`: Runs the basic verifiers.
- `make rotate-wg-key peer=<name>`: Rotates a specific WireGuard peer’s key, updates rendered server/client configs, and archives the prior client config.
- SPA artifacts: Deployment is artifact-based. Control router SPA daemon version with `SPA_PQ_VERSION` in `.env` (tag or `latest`). Router downloads binary + `.sha256`, optionally verifies with GPG if `SPA_PQ_SIG_URL` and `/etc/spa/pubkey.gpg` are set, verifies sha256, and installs to `/usr/local/bin/home-secnet-spa-pq`.
- Remote logging: Enable rsyslog forwarding by setting `RSYSLOG_FORWARD_ENABLE=true` and `RSYSLOG_REMOTE=host:port` in `.env`.
- `make spa`: Builds PQ-KEM SPA server and client crates.

Providers
Winder runs on a plain Debian/Ubuntu host by default (baremetal). Proxmox is optional and supported via an adapter.

- Baremetal (default): the current host acts as the router. `make -C home-secnet router` performs a provider‑aware host step, then renders and applies the router configuration locally. The host step previews network changes by default. You can apply them interactively with the `--apply` flag described below.
- Proxmox (optional): when Proxmox tools are detected, setup offers to use the proxmox provider. Bridges (`vmbr*`), VM creation (`qm`), and node firewall are handled by adapter scripts; rendering and apply proceed as usual.

Baremetal Network Configure (Preview or Apply)
Use `home-secnet/scripts/providers/baremetal/configure_network.sh` to select WAN/LAN interfaces quickly and generate a minimal netplan for a router host.

- Preview (no changes): `bash home-secnet/scripts/providers/baremetal/configure_network.sh`
- Apply (writes netplan and prompts to reboot networking): `bash home-secnet/scripts/providers/baremetal/configure_network.sh --apply`

During apply, you’ll be prompted to choose WAN and LAN from detected NICs. The script writes a netplan file under `/etc/netplan/99-winder.yaml`, backs up existing files to `/etc/netplan/*.bak-<ts>`, and runs `netplan try` (with a 120‑second rollback window) to avoid lockouts. You can abort safely during the timer.

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
- SPA (Single Packet Authorization): set `SPA_ENABLE=true` to gate WireGuard. Only `SPA_MODE=pqkem` is supported (post‑quantum KEM + HMAC). CI builds the SPA daemon and publishes artifacts; deployments fetch the release binary rather than compiling on-router. Control version via `SPA_PQ_VERSION` in `.env`.

Double-Hop Egress (Optional)
- Enable with `DOUBLE_HOP_ENABLE=true` and fill `WG2_*` in `.env`. This creates `/etc/wireguard/wg1.conf` on the router and policy routes WG client traffic out via the remote exit node. Configure the exit node to accept `${WG2_ADDRESS}` and allow forwarding/NAT.

DNS Options
- Default: AdGuard Home with encrypted upstreams and DNSSEC, serving LAN and WG on port 53.
- Alternative: set `DNS_STACK=unbound` in `.env`, re‑render, and push for local validating recursion.
- To offer DoH/DoQ directly to clients via AdGuard Home, configure a trusted certificate and enable HTTPS listeners.

Suricata & Logging
- Suricata is configured inline on VLAN subinterfaces. Tune with `suricata-update` on the Router VM.
- EVE JSON logs at `/var/log/suricata/eve.json`; logs are stored locally in `/var/log/secure/` for centralized access.

Proxmox Firewall
- Node firewall rules are rendered from `.env` and installed during the flow.
- Default inbound DROP; SSH allowed from TRUSTED; `:8006` allowed only from WG and localhost.

Security Highlights
- SSH key‑only access; local passwords disabled where possible.
- nftables default‑drop with inter‑VLAN isolation.
- DHCP/DNS bound to VLANs and WG only.
- Daily maintenance: unattended‑upgrades, Lynis audit, rkhunter/chkrootkit, and ClamAV on host and router.
- Alerts: emails to `ALERT_EMAIL` on update errors, reboot‑required, audit warnings, or detections. Optional SMTP relay via msmtp (`SMTP_ENABLE=true`).
- Remote logging: enable rsyslog forwarding by setting `RSYSLOG_FORWARD_ENABLE=true` and `RSYSLOG_REMOTE=host:port`. Auth, Suricata, and SPA logs are forwarded off‑box for tamper‑resistant audit trails.

Traffic Shaping
- fq_codel enabled on LAN. Basic rate limiting is supported; more advanced padding/morphing may be added later.

Next Steps
- Connect a peer using `clients/wg-client1.conf` (or generate a QR with `qrencode`).
- Move LAN devices to the correct VLAN ports on your switch.
- Optionally route Proxmox updates through the Router VM’s WireGuard egress.

Notes & Limitations
- Some downloads (e.g., images) are best‑effort and may require retries.
- Static WAN: adjust the rendered netplan or extend the render step to write static WAN from `.env`.
- Email alerts require a mailer. Set SMTP vars in `.env` to relay.

Quick Start
- Defaults: AdGuard Home with Quad9 DoT and DNSSEC, SPA-gated WireGuard, nftables default-deny.
- Prereqs: Ubuntu 24.04 host, bash, curl, ssh, nft, wg, `cargo` optional.
- Steps:
  - Clone repo and `cd home-secnet`.
  - Run `make all` to set up `.env`, detect NICs, render, and apply.
  - Review and adjust `.env` via `home-secnet/scripts/setup_env.sh` (idempotent).
  - Re-apply router configs anytime with `make router`.

Baremetal Host Networking
- Provider detection: scripts choose Proxmox if tools are present; otherwise baremetal.
- Baremetal flow:
  - `home-secnet/scripts/configure_host.sh` applies host firewall and prerequisites.
  - `home-secnet/scripts/apply_router_configs.sh` pushes rendered configs to the router VM/host.
  - Netplan and nftables are rendered from templates under `home-secnet/router/configs/`.

Air-gapped SPA
- Pre-stage SPA artifacts under `home-secnet/render/opt/spa` to avoid network access on the router during install.
- Files: `home-secnet-spa-pq`, `home-secnet-spa-pq-client`, `token.json`, optional `token.sig`, optional `pubkey.gpg`.
- Place these under `home-secnet/render/opt/spa/` before running `make router`.

Security Best Practices
- DNS: AdGuard defaults to DoT upstreams (Quad9 primary) with DNSSEC; UI binds to `127.0.0.1` by default. Use SSH tunnel for UI access.
- SPA: PQ‑KEM (Kyber‑768 + HMAC) defaults on; see `docs/SPA_PQ.md`.
- nftables: default‑deny; chain names match templates in `home-secnet/router/configs/`.
- Scanners (optional): set `SECURITY_SCANNERS_ENABLE=true` in `home-secnet/.env`, then run `make security-enable` to copy scripts and enable timers on the router.
- Traffic shaping: enable by setting `SHAPING_EGRESS_KBIT` (and optionally `SHAPING_INGRESS_KBIT`) in `.env`. Scripts prefer CAKE and fall back to HTB+fq_codel. DSCP can be enabled via `SHAPING_DSCP_ENABLE=true`.

Proxmox Provider (Appendix)
- Node firewall groups and rules: `home-secnet/proxmox/`.
- Router VM creation: `home-secnet/scripts/providers/proxmox/create_router_vm.sh`.
- After provisioning, run `make router` to render and apply configs.
SPA (PQ‑KEM) Summary
- Default SPA mode: `pqkem` using ML‑KEM/Kyber‑768 and HMAC‑SHA256.
- Daemon: `home-secnet/router/spa-pq` runs on the router, listening on `SPA_PQ_PORT`, inserting ephemeral allow rules into nftables chain `wg_spa_allow` for `OPEN_SECS`.
- Client: Rust tool under `home-secnet/clients/spa-pq-client` sends a single knock. Client config template is written to `clients/spa-pq-client.json` during render.
- See `docs/SPA_PQ.md` for packet format, variables, and troubleshooting.

