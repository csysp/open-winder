AGENTS.md

Scope
- Applies to the entire repository unless a more specific AGENTS.md appears in a subdirectory.
- Use this document as the default operating manual for agents and contributors working on this codebase.

Principles (Rust Book–inspired)
- Safety first: prefer designs that fail fast, validate inputs early, and avoid partial/undefined states. Scripts must exit on error.
- Explicit over implicit: make side effects, assumptions, and preconditions visible in code and docs.
- Ownership mindset: own the lifecycle of resources you create (files, VM artifacts, bridges, temporary state). Always clean up or make work idempotent.
- Composability: small, focused functions and scripts that compose into larger flows. Avoid monoliths.
- Predictability: deterministic outputs given the same inputs (.env and host state). Idempotent operations wherever feasible.
- Documentation as part of the deliverable: keep runbooks and usage examples close to the code that implements them.
- Least privilege: never require more access than needed; do not log or commit secrets. Treat .env as sensitive; only .env.example belongs in git.

Repository Conventions
- Directory layout
  - `home-secnet/` — primary project for Proxmox-based home network automation.
  - `home-secnet/scripts/` — orchestration and helpers; pure bash.
  - `home-secnet/router/` — golden config templates, cloud-init, rendered outputs go to `home-secnet/render/` (ignored by git).
  - `home-secnet/tests/` — non-destructive verifiers and health checks.
  - `home-secnet/.env.example` — documented environment template. Never commit a real `.env`.
- Artifacts
  - Rendered content must go under `home-secnet/render/` and clients under `home-secnet/clients/` (both ignored).
  - Temporary work should be under a unique path in `/tmp` (on Linux hosts) such as `/tmp/winder-<script>-<pid>`.

Bash Scripting Style
- Shebang and strict mode
  - Start every script with `#!/usr/bin/env bash`.
  - Enable strict mode at the top: `set -euo pipefail` and `IFS=$'\n\t'`.
  - Prefer `readonly` for constants and `local` for function-scoped variables.
- Functions
  - Name with `snake_case` and action-first verbs: `render_router_configs`, `apply_node_firewall`.
  - Keep functions small (≤ 40–50 lines). Extract helpers in `scripts/lib/` when reused.
  - Return values via exit codes (0 success) and explicit output via `echo`/`printf`.
- Arguments and usage
  - Parse options with `getopts` where applicable. Provide a `usage()` that documents flags and environment variables.
  - Validate required inputs early and exit with a helpful message.
- Logging
  - Provide helpers: `log_info`, `log_warn`, `log_error`, `die`. Support `VERBOSE=1` to enable more detail; never echo secrets.
  - For noisy external commands, prefer a `run` wrapper that logs the command before execution.
- External commands
  - Guard with `command -v <tool> >/dev/null 2>&1 || die "missing <tool>"` in preflight checks.
  - Always double-quote interpolations to avoid globbing and word-splitting.
- Filesystem operations
  - Use `mkdir -p` before writes; use `chmod`/`umask` to set intended permissions.
  - Write files atomically when possible: render to temp, then `mv` into place.
- Idempotency & safety
  - Make scripts safe to re-run. Check existence before creating, use declarative configs, and avoid destructive defaults.
  - When destructive actions are needed, add explicit prompts or `--yes` flags.
- Networking & SSH
  - Use `ssh`/`scp` with non-interactive, secure defaults; avoid leaking host keys and credentials. Prefer `-o StrictHostKeyChecking=accept-new` for first connections.
  - For remote execution, capture and propagate exit codes.

Makefile Conventions
- `SHELL := /bin/bash` and keep targets idempotent.
- Declare `.PHONY` for non-file targets.
- Group flows into coarse targets: `all`, `router`, `checks`, and avoid hidden side effects.
- Keep environment passing explicit; read `.env` in scripts rather than parsing in Make.

Templates and Configuration
- Treat files in `router/configs/` and `router/cloudinit/` as source-of-truth templates.
- Rendered files must never be committed. Ensure `.gitignore` covers `render/` and `clients/`.
- Environment
  - `.env.example` documents every variable with sane defaults or placeholders.
  - `scripts/setup_env.sh` should be the only wizard that writes `.env`. Never modify `.env` silently elsewhere.

Testing & Verification
- Tests live in `home-secnet/tests/` and run with `set -euo pipefail`.
- Tests should be fast and safe; prefer read-only checks or operations against test sandboxes.
- Add a check for each critical subsystem (WireGuard, DNS, isolation, IDS, SPA, etc.).

Documentation
- Keep `README.md` in the repo root short and opinionated; the detailed runbook lives in `home-secnet/README.md`.
- Every script starts with a brief header: purpose, inputs, outputs, side effects.
- Update docs with changes in behavior or new flags as part of the same PR/commit.

Commit & Review Guidelines
- Write focused commits with imperative subject lines:
  - `feat: ...` new capability
  - `fix: ...` bug fix
  - `docs: ...` documentation only
  - `refactor: ...` no behavior change
  - `chore: ...` tooling / CI / non-code
- Keep changes minimal and localized. Update tests/docs together with code changes.

Agent Operating Notes
- Before editing, scan for an AGENTS.md in the working subtree; more nested files override root guidance.
- Do not break existing flows when adding new features; make them opt-in via `.env` flags.
- Prefer small patches over broad refactors unless explicitly requested.
- If a command would be destructive, ask for approval.

Security Posture
- Default-deny for network listeners; bind only to required interfaces.
- Do not log secrets or commit sensitive files. `.env` is never committed.
- Validate untrusted inputs, sanitize file paths, and confirm host/distro assumptions.

Style Check Shortlist (copy/paste at top of new scripts)
- `#!/usr/bin/env bash`
- `set -euo pipefail; IFS=$'\n\t'`
- Guard inputs; document flags; no secrets in logs; idempotent steps; atomic writes.

Docs Consistency Guide
- Defaults
  - Refer to the router system as “Winder”. The `home-secnet/` directory name is an implementation detail.
  - PQ‑KEM SPA (Kyber‑768 + HMAC) is the SPA mode. Legacy fwknop has been removed.
- Sources of truth
  - Top‑level overview and links: `README.md`.
  - Runbook, scripts, env vars, and targets: `home-secnet/README.md`.
  - SPA control‑plane details: `docs/SPA_PQ.md`.
- When updating code, update docs in the same PR:
  - New env vars → add to `home-secnet/.env.example` and document in `home-secnet/README.md`.
  - New/changed scripts or Make targets → reflect in runbook steps and Make Targets section.
  - NFTables or systemd changes → ensure chain names, flags, and unit args match in `docs/SPA_PQ.md`.
- Paths in docs must be exact and clickable (use repo‑relative paths like `home-secnet/scripts/...`).
- CI notes in `README.md` must reflect current workflows (fmt, clippy, shellcheck, secrets scan, debug).
- PR checklist (copy into PR description):
  - [ ] Updated `.env.example` and documented new variables.
  - [ ] Updated runbook for any script/Make changes.
  - [ ] Updated SPA docs if packet, nftables, or service args changed.
  - [ ] Verified links and paths resolve.
  - [ ] CI is green (fmt, clippy, build/tests, shellcheck, secrets scan).
