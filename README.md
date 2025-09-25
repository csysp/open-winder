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
