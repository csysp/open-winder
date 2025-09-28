Winder (Router System)

Design vision: OpenWRT-only. This branch targets an OpenWRT-based Winder image with overlayed hardening (SPA-gated WireGuard, nftables, AdGuard+Unbound DNSSEC). Legacy Proxmox/Ubuntu VM automation is not supported here; see `docs/legacy_proxmox.md`.

Quick Start (OpenWRT)
- Configure: copy `home-secnet/.env.example` to `.env` and adjust `OPENWRT_VERSION`, `OPENWRT_TARGET`, `OPENWRT_PROFILE`, interfaces, WG/SPA vars.
- Render overlay: `make -C home-secnet openwrt-render`
- Build image: `make -C home-secnet openwrt-build`
- Flash image (destructive): `make -C home-secnet openwrt-flash device=/dev/sdX image=<path>`
- Optional: stage SPA binary at `home-secnet/render/opt/spa/home-secnet-spa-pq` before render to embed it into the image. Otherwise, provision `/usr/bin/home-secnet-spa-pq` post‑boot.

Pre-Alpha / Pre-Release
This project is pre-alpha. Expect rapid iteration. Legacy VM flow: see `docs/legacy_proxmox.md`.

Make Targets
- OpenWRT flow: `openwrt-render`, `openwrt-build`, `openwrt-flash`, `checks-openwrt`
- Dev: `spa`, `fmt`, `clippy`, `rotate-wg-key peer=<name>`

Legacy Flow
- See `docs/legacy_proxmox.md` for the deprecated Proxmox/Ubuntu VM automation overview and migration notes.

Baremetal (OpenWRT Image)
- Build a pinned OpenWRT image with the overlay; flash to storage; boot the device.

Assumptions & Prereqs
- OpenWRT ImageBuilder for your target; enough storage to build and flash; two NICs recommended.

Network Models
- Two‑NIC recommended: `vmbr0` for WAN, `vmbr1` for LAN/VLAN trunk.
- One‑NIC fallback: WAN on `vmbr0`. Separate LAN is not possible without a second NIC; scripts warn and let you abort.

WireGuard Access
- `wg0` defined in `/etc/config/network`; private key set from `.env` or auto-generated on first boot if empty.
- SPA gates UDP `${WG_PORT}` via nft set with timeout. Service `spa-pq` manages allow set.

Double-Hop Egress (Optional)
- Enable with `DOUBLE_HOP_ENABLE=true` and fill `WG2_*` in `.env`. This creates `/etc/wireguard/wg1.conf` on the router and policy routes WG client traffic out via the remote exit node. Configure the exit node to accept `${WG2_ADDRESS}` and allow forwarding/NAT.

DNS Options
- Default: AdGuard Home listens on LAN+WG and forwards to Unbound (validating, DNSSEC) at `127.0.0.1:5353`.
- AdGuard UI binds `127.0.0.1:3000` by default; use an SSH tunnel for access.

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

Baremetal Host Networking
- OpenWRT image with overlay. No Proxmox/Ubuntu VM configuration in this branch.

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

Appendix
- The legacy Proxmox/Ubuntu VM flow remains in `legacy/proxmox`.
SPA (PQ‑KEM) Summary
- Default SPA mode: `pqkem` using ML‑KEM/Kyber‑768 and HMAC‑SHA256.
- Daemon: `home-secnet/router/spa-pq` runs on the router, listening on `SPA_PQ_PORT`, inserting ephemeral allow rules into nftables chain `wg_spa_allow` for `OPEN_SECS`.
- Client: Rust tool under `home-secnet/clients/spa-pq-client` sends a single knock. Client config template is written to `clients/spa-pq-client.json` during render.
- See `docs/SPA_PQ.md` for packet format, variables, and troubleshooting.
