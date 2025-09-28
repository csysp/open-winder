Winder (Router System)

Overview
- Winder builds on OpenWRT to provide a hardened router image with an overlay: SPA‑gated WireGuard, nftables default‑deny, and AdGuard Home + Unbound (validating DNSSEC). This branch is OpenWRT‑only.
- Designed for home labs and privacy‑conscious users who want a reproducible, hardened router image on OpenWRT.
- OpenWRT is an outstanding, community‑driven project. Please support and refer to https://openwrt.org for documentation, device support, and ImageBuilder details.
- For the deprecated VM automation, see `docs/legacy_proxmox.md`.

Quick Start
- 1) Run the wizard (local repo):
  - `bash home-secnet/scripts/install.sh`
  - Fewer prompts: `bash home-secnet/scripts/install.sh --yes`
- 2) Render overlay:
  - `make -C home-secnet openwrt-render`
- 3) Build image (pinned ImageBuilder):
  - Ensure `.env` has `OPENWRT_VERSION`, `OPENWRT_TARGET`, `OPENWRT_PROFILE`, `OPENWRT_SHA256`
  - `make -C home-secnet openwrt-build`
  - Output: `home-secnet/render/images/`
- 4) Flash image (destructive):
  - `make -C home-secnet openwrt-flash device=/dev/sdX image=home-secnet/render/images/<file>`
- 5) First boot:
  - Connect to LAN; follow your device’s OpenWRT install notes if needed.

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
- Safety
  - Flashing is destructive. Double-check `device=/dev/sdX` and the chosen image.

Requirements
- Host tools: bash, curl, tar, xz, sha256sum, rsync, ssh. ripgrep (rg) optional for lint.
- Disk space: ~5–10 GB free for ImageBuilder and artifacts.
- Network: two NICs recommended (WAN/LAN). For virtualization hosts, see Proxmox Bridges below.

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

Pre-Alpha / Pre-Release
- This project is pre-alpha. Expect rapid iteration. Legacy VM flow: see `docs/legacy_proxmox.md`.
