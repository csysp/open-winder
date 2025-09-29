Installer (One-Liner) – OpenWRT Only

Design
- OpenWRT-only. MODE is enforced to `openwrt`.
- Pinned, checksummed artifacts when network fetch is required; otherwise local.

Local (repo-cloned) usage
- Primary path is the orchestrator, which runs the wizard, renders, builds, and can flash:
  - bash home-secnet/scripts/open-winder-setup.sh --yes
  - sudo bash home-secnet/scripts/open-winder-setup.sh --yes --flash device=/dev/sdX

Intended tagged one-liner (for releases)
- curl -fsSL https://example.com/winder/releases/download/vX.Y.Z/install.sh | bash
- The script will download a pinned `wizard.sh` and verify its checksum before execution.

Wizard responsibilities
- Validate basic tools and OS assumptions (non-fatal warnings unless critical).
- Create/update `.env` via the existing `setup_env.sh` (idempotent, atomic upsert).
- Optionally configure Proxmox vmbr0/vmbr1 bridges if Proxmox is detected.
- Render overlay artifacts for OpenWRT under `home-secnet/render/`.

Next steps after wizard
- make -C home-secnet openwrt-build
- make -C home-secnet openwrt-flash device=/dev/sdX image=<path>

Security
- Never fetch “latest”. Installers require version-pinned URLs + SHA256.
- `.env` is never committed; `.env.example` documents variables.
