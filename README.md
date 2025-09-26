Winder

Winder is a turn‑key router system for a Proxmox‑based, WireGuard‑first home network. It provisions an Ubuntu Router VM with hardened networking, optional DNS stacks, IDS, and SPA‑gated WireGuard access using a post‑quantum KEM control plane by default.

Start Here
- Read `home-secnet/README.md` for the full runbook and architecture.
- Copy `home-secnet/.env.example` to `home-secnet/.env` and edit values.
- Use `home-secnet/Makefile` targets or the scripts under `home-secnet/scripts/`.

Quick Links
- Runbook: `home-secnet/README.md`
- Env template: `home-secnet/.env.example`
- Make targets: `home-secnet/Makefile`
- PQ SPA: `docs/SPA_PQ.md`

Script Help
- All top-level scripts under `home-secnet/scripts/` support `-h`/`--help` and print purpose, inputs, and side effects.

CI & Quality Gates
- Rust server and client crates: fmt, clippy (-D warnings), build, and tests on every push/PR.
- Shell scripts: linted with shellcheck (non-fatal until fully clean).
- Secrets scanning: Gitleaks runs on working tree and full git history.
- Debug workflow: on-demand build with debuginfo for server/client artifacts.

Manually run scans/builds
- Secrets: GitHub Actions → Secrets Scan → Run workflow.
- Debug: GitHub Actions → Debug → Run workflow (select target).

Notes
- Scripts are intended to run on a Proxmox host for provisioning and configuration; the SPA daemon runs on the Router VM.
- CI builds the PQ SPA server/client crates, runs fmt/clippy/tests, lints shell scripts, and performs secrets scanning on each push.

Ultralight Mode
- Purpose: run Winder on Atom/Celeron-era x86, NUCs, thin clients, or Pi 4/5 with minimal footprint.
- Keeps: WireGuard + SPA‑PQ (Kyber‑then‑HMAC), nftables default‑drop, deny‑by‑default per‑VLAN, fq_codel, Proxmox UI over WG only.
- Replaces/Disables: Suricata off; DHCP via dnsmasq; DNS via Unbound by default; minimal logging.
- Enable: during `home-secnet/scripts/setup_env.sh` you’ll be prompted to enable Ultralight. Settings persist to `home-secnet/.env`.
- Apply: run normal flow or `make -C home-secnet ultralight` to render/apply the minimal stack.
- Health: on the router VM, run `/usr/local/sbin/ul_health.sh` to print a quick status (nftables, DNS, shaping, WG port).
