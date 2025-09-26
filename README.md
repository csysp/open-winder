Winder

Winder is a turn-key router system for a Proxmox-based, WireGuard-first home network. It provisions an Ubuntu Router VM with hardened networking, optional DNS stacks, IDS, and SPA-gated WireGuard access using a post-quantum KEM control plane by default.

Pre-Alpha / Pre-Release
- This repository is pre-alpha. Expect rapid changes and breaking updates.
- For installs, prefer the main-branch installer while releases are paused:
  - curl -fsSL https://raw.githubusercontent.com/csysp/winder/main/home-secnet/scripts/install_winder.sh -o /tmp/install_winder.sh
  - chmod +x /tmp/install_winder.sh
  - /tmp/install_winder.sh

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

Air-Gapped SPA Deployment
- Pre-stage SPA artifacts on the provisioning host and avoid network fetches during apply:
  - Build (or obtain) binaries: `home-secnet/router/spa-pq/target/release/home-secnet-spa-pq` and `home-secnet/clients/spa-pq-client/target/release/home-secnet-spa-pq-client`.
  - Create a token JSON with SHA256s (and optionally sign it with GPG or cosign). Example keys placed alongside token:
    - `home-secnet/render/opt/spa/token.json`, `home-secnet/render/opt/spa/token.sig`, and either `home-secnet/render/opt/spa/pubkey.gpg` or `home-secnet/render/opt/spa/cosign.pub`.
  - Place artifacts under `home-secnet/render/opt/spa/` before running apply.
- The apply step installs from `render/opt/spa/`, verifies signature (if keys provided) and checks SHA256s, then enables the SPA daemon. No network fetch occurs when pre-staged.
- For constrained systems, skip Rust toolchain on the host and pre-build on a separate build machine.

Air-Gapped SPA Deployment
- Pre-stage SPA artifacts on the provisioning host and avoid network fetches during apply:
  - Build (or obtain) binaries: `home-secnet/router/spa-pq/target/release/home-secnet-spa-pq` and `home-secnet/clients/spa-pq-client/target/release/home-secnet-spa-pq-client`.
  - Create a token JSON with SHA256s (and optionally sign it with GPG or cosign). Example keys placed alongside token:
    - `render/opt/spa/token.json`, `render/opt/spa/token.sig`, and either `render/opt/spa/pubkey.gpg` or `render/opt/spa/cosign.pub`.
  - Place artifacts under `home-secnet/render/opt/spa/` before running apply.
- The apply step installs from `render/opt/spa/`, verifies signature (if keys provided) and checks SHA256s, then enables the SPA daemon.
- For constrained systems, skip Rust toolchain on the host and pre-build on a separate build machine.

Ultralight Mode
- Purpose: run Winder on Atom/Celeron-era x86, NUCs, thin clients, or Pi 4/5 with minimal footprint.
- Keeps: WireGuard + SPA‑PQ (Kyber‑then‑HMAC), nftables default‑drop, deny‑by‑default per‑VLAN, fq_codel, Proxmox UI over WG only.
- Replaces/Disables: Suricata off; DHCP via dnsmasq; DNS via Unbound by default; minimal logging.
- Experimental (Pre-Alpha): Ultralight is disabled by default and hidden in the wizard. Set `ULTRALIGHT_EXPERIMENTAL=1` before running `setup_env.sh` to see the prompt. This path may require precompiled SPA artifacts and external build hosts.
- Apply: run normal flow or `make -C home-secnet ultralight` to render/apply the minimal stack.
- Health: on the router VM, run `/usr/local/sbin/ul_health.sh` to print a quick status (nftables, DNS, shaping, WG port).
