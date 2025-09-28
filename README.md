open-winder builds on OpenWRT to provide a hardened router image with an overlay: SPA‑gated WireGuard, Hysteria2 QUIC wrapper, Suricata overtop nftables and AdGuard Home + Unbound (validating DNSSEC).
OpenWRT is an outstanding, community‑driven project that I personally admire alot.
Please support and refer to https://openwrt.org for documentation, device support, and ImageBuilder details.

This project is early in development. Expect rapid iteration and general slop code.

Quick Start
- One-click (safe, no flash):
  - `bash home-secnet/scripts/oneclick.sh --yes`
- One-click + flash (destructive):
  - `sudo bash home-secnet/scripts/oneclick.sh --yes --flash device=/dev/sdX`
- Output images: `home-secnet/render/images/`
- First boot: connect to LAN; follow your device's OpenWRT install notes.

Details: Build & Flash
- Choose OpenWRT values
  - `OPENWRT_VERSION`: release tag (e.g., 23.05.3).
  - `OPENWRT_TARGET`: target path segment (e.g., `x86/64`, `mediatek/filogic`).
  - `OPENWRT_PROFILE`: device profile (list via ImageBuilder “make info”).
  - `OPENWRT_SHA256`: checksum of the ImageBuilder tar.xz (from downloads.openwrt.org).
- Packages and overlay
  - Optional extra packages via `OPENWRT_PACKAGES="pkg1 pkg2"`.
  - The build uses `render/` as a files overlay (e.g., SPA binaries under `render/opt`).
- Output
  - Built images are written to `home-secnet/render/images/`.

Optional: Proxmox Bridges
- Optional — Proxmox only: set up `vmbr0` (WAN) and `vmbr1` (LAN) out of the box.
- Use the wizard (it will prompt), or run explicitly:
  - `sudo make -C home-secnet hypervisor-setup YES=1 PHYS_WAN_IF=<wan> PHYS_LAN_IF=<lan>`
- This writes `/etc/network/interfaces.d/bridges`. Apply with `ifreload -a` (network disruption expected).

Make Targets
- OpenWRT flow: `openwrt-render`, `openwrt-build`, `openwrt-flash`, `checks-openwrt`
- Checks: `checks-openwrt` runs lint + tests.

Security & Options (Short)
- DNS: AdGuard Home → Unbound (validating DNSSEC). UI binds `127.0.0.1:3000` by default; use SSH tunnel.
- WireGuard & SPA: `wg0` is configured; SPA gates UDP `${WG_PORT}` via an nftables allow‑set.
- Traffic shaping (optional): set `SHAPING_EGRESS_KBIT` (`SHAPING_INGRESS_KBIT` optional). CAKE preferred; HTB+fq_codel fallback.
- Double‑hop (optional): set `DOUBLE_HOP_ENABLE=true` and `WG2_*` in `.env` for upstream egress via another WireGuard exit.
- Logging (optional): set `RSYSLOG_FORWARD_ENABLE=true` and `RSYSLOG_REMOTE=host:port` to forward SPA/auth/IDS logs.
- SPA details: see `docs/SPA_PQ.md`.
- IDS: Suricata enabled by default (LAN `br-lan`). Overlay renders `/etc/suricata/suricata.yaml`; build auto-adds `suricata`; logs at `/var/log/suricata/eve.json`.

Requirements
- Host tools: bash, curl, tar, xz, sha256sum, rsync, ssh. ripgrep (rg) optional for lint.
- Disk space: ~5–10 GB free for ImageBuilder and artifacts.
- Network: two NICs needed (WAN/LAN). For virtualization hosts, see Proxmox Bridges below.

Licensing
This repository is licensed under GNU GPL-2.0-only. See `LICENSE`.
Images built with this repository include OpenWRT and upstream packages and are governed by their respective licenses (primarily GPL-2.0). See https://openwrt.org for details.
