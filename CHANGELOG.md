Changelog

0.1.1

- Setup wizard improvements
  - Load defaults early from .env.example then .env (strict-mode safe)
  - Defaults: WRAP_MODE=hysteria2, DNS_STACK=unbound, SPA_ENABLE=true, DOUBLE_HOP_ENABLE=true
  - Randomize WG_PORT once and persist immediately
  - Early NIC detection and .env reload
  - Require non-empty Proxmox node name
  - Atomic .env updates (no duplicate keys)
- Installer
  - Add install_winder.sh and pin to v0.1.1 tarball
- Nftables
  - Ultralight dedicated table without flushing global rules; persisted includes

0.1.0 (alpha)

- Features
  - Ultralight mode: dnsmasq + Unbound, nftables dedicated table (no flush), shaping helper, health helper
  - SPA‑PQ control plane (Kyber‑then‑HMAC), WireGuard‑gated access
  - Proxmox automation: bridges, VM creation, render/apply configs
  - Make targets and verification scripts
- Security & safety
  - Default‑deny nftables; SSH over WG only; SPA window for WG
  - Strict bash scripts with cleanup and explicit logging; safer SSH host key policy (accept‑new)
  - Preflight hardening for apt installs
- Developer experience
  - `-h/--help` across scripts; improved logging
  - Makefile clean path fix; removal of backup files
- Notes
  - Ultralight is opt‑in via setup prompt
  - Nftables persists via includes; no ruleset flush
  - Suricata disabled in Ultralight; full mode can enable IDS later
