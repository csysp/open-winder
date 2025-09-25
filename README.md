Winder

This repo contains automation and scripts for homelab networking and security. The primary project is `home-secnet`, a turn‑key setup for a Proxmox‑based, WireGuard‑first home network with an Ubuntu Router VM and optional Logging VM.

Start here
- Read `home-secnet/README.md` for the full runbook and architecture.
- Copy `home-secnet/.env.example` to `.env` inside the `home-secnet` folder and edit values.
- Use the scripts in `home-secnet/scripts/` or the provided `Makefile` targets.

Quick links
- Docs: `home-secnet/README.md`
- Env template: `home-secnet/.env.example`
- Make targets: `home-secnet/Makefile`
 - PQ SPA: `docs/SPA_PQ.md`

Notes
- These scripts are intended to run on a Proxmox host for provisioning and configuration.
