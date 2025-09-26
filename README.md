Winder

Winder is a turn-key router system for a Proxmox-based, WireGuard-first home network. It provisions an Ubuntu Router VM with hardened networking, optional DNS stacks, IDS, and SPA-gated WireGuard access using a post-quantum KEM control plane by default.

Pre-Alpha / Pre-Release`nThis repository is pre‑alpha. Expect rapid changes and breaking updates. While releases are paused, install from main with the one‑liner installer: `curl -fsSL https://raw.githubusercontent.com/csysp/winder/main/home-secnet/scripts/install_winder.sh -o /tmp/install_winder.sh && chmod +x /tmp/install_winder.sh && /tmp/install_winder.sh`. The full runbook lives in `home-secnet/README.md`, and the environment example is at `home-secnet/.env.example`.
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

CI & Quality Gates`nOn every push or pull request, Rust crates run fmt and clippy with warnings as errors, then build and tests. Shell scripts are linted with ShellCheck, and secrets scanning runs across the working tree and history. A debug workflow builds artifacts with debuginfo on demand.`n`nNotes
- Scripts are intended to run on a Proxmox host for provisioning and configuration; the SPA daemon runs on the Router VM.
- CI builds the PQ SPA server/client crates, runs fmt/clippy/tests, lints shell scripts, and performs secrets scanning on each push.

Air‑Gapped SPA Deployment`nFor high‑security or offline setups, pre‑stage the SPA server and client binaries plus a token describing their hashes (with an optional signature). Place `home-secnet-spa-pq`, `home-secnet-spa-pq-client`, `token.json` (and `token.sig` with `pubkey.gpg` or `cosign.pub`) under `home-secnet/render/opt/spa/` before applying. The installer performs no network fetch in this mode; it verifies the token when keys are provided, compares SHA256s, and installs the SPA daemon. If your Proxmox host is constrained or air‑gapped, build SPA on a separate machine and copy the artifacts.`n`nUltralight Mode`nUltralight aims to run Winder on Atom/Celeron‑era x86, NUCs, thin clients, or Pi 4/5 with a minimal footprint. It keeps WireGuard + SPA‑PQ, default‑drop nftables, deny‑by‑default per‑VLAN rules, and fq_codel, and pares back heavier components. It is experimental and disabled by default in this pre‑alpha; set `ULTRALIGHT_EXPERIMENTAL=1` before running `setup_env.sh` to see the prompt. Apply with `make -C home-secnet ultralight` when testing; on the router VM, `/usr/local/sbin/ul_health.sh` prints a brief status.
