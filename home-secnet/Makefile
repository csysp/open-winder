SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: all spa router checks clean help host

help:
	@echo "Targets: all | router | checks | clean"
	@echo "Dev: fmt | clippy"
 	@echo "Utils: detect-hypervisor"

all: spa
	bash scripts/preflight.sh
	bash scripts/setup_env.sh
	bash scripts/detect_nics.sh
	$(MAKE) host
	bash scripts/render_router_configs.sh
	bash scripts/apply_router_configs.sh
	@if grep -q '^SECURITY_SCANNERS_ENABLE=true' .env 2>/dev/null; then \
	  bash scripts/setup_security_maintenance.sh; \
	else \
	  echo "[security] scanners disabled (set SECURITY_SCANNERS_ENABLE=true to enable)"; \
	fi
	bash scripts/verify_deploy.sh

spa:
	# Build SPA server and client (Rust)
	@if command -v cargo >/dev/null 2>&1; then \
		( cd router/spa-pq && cargo build --release ); \
		( cd clients/spa-pq-client && cargo build --release ); \
	else \
		echo "cargo not found; skipping local SPA build"; \
	fi

router: spa
	$(MAKE) host
	bash scripts/render_router_configs.sh
	bash scripts/apply_router_configs.sh
 	@if grep -q '^SECURITY_SCANNERS_ENABLE=true' .env 2>/dev/null; then \
	  bash scripts/setup_security_maintenance.sh; \
	else \
	  echo "[security] scanners disabled (set SECURITY_SCANNERS_ENABLE=true to enable)"; \
	fi

checks:
	bash scripts/env_doctor.sh 
	bash tests/verify_wg.sh 
	bash tests/verify_dns.sh 
	bash tests/verify_isolation.sh 
	bash tests/verify_ids.sh 
	bash tests/verify_spa.sh 
	bash tests/spa_unit.sh 

clean:
	rm -rf home-secnet/render/ home-secnet/clients/

fmt:
	@if command -v cargo >/dev/null 2>&1; then \
		cargo fmt --manifest-path router/spa-pq/Cargo.toml --all ; \
		cargo fmt --manifest-path clients/spa-pq-client/Cargo.toml --all ; \
	else \
		echo "cargo not found; skipping fmt"; \
	fi

clippy:
	@if command -v cargo >/dev/null 2>&1; then \
		cargo clippy --manifest-path router/spa-pq/Cargo.toml --all-targets -- -D warnings ; \
		cargo clippy --manifest-path clients/spa-pq-client/Cargo.toml --all-targets -- -D warnings ; \
	else \
		echo "cargo not found; skipping clippy"; \
	fi
rotate-wg-key:
	@if [ -z "$(peer)" ]; then echo "Usage: make rotate-wg-key peer=<peer_name>"; exit 1; fi
	bash scripts/rotate_wg_key.sh --peer "$(peer)"
.PHONY: ultralight
ultralight:
	@echo "Rendering Ultralight Mode..."
	bash scripts/render_router_configs.sh
	bash scripts/apply_router_configs.sh
host:
	bash scripts/configure_host.sh

.PHONY: detect-hypervisor
detect-hypervisor:
	bash scripts/detect_hypervisor.sh

.PHONY: security-enable
security-enable:
	@if ! grep -q '^SECURITY_SCANNERS_ENABLE=true' .env 2>/dev/null; then \
	  echo "Set SECURITY_SCANNERS_ENABLE=true in .env first"; exit 1; \
	fi
	@echo "[security] Copying optional scanners to router and enabling timers..."
	@bash -c 'set -euo pipefail; IFS="\n\t"; \
	  ROOT_DIR="$$(pwd)"; \
	  source home-secnet/.env; \
	  if [ -z "$${ROUTER_IP:-}" ]; then echo "ROUTER_IP not set in .env"; exit 1; fi; \
	  ssh -o StrictHostKeyChecking=accept-new $${ROUTER_ADMIN_USER}@$${ROUTER_IP} "sudo install -d -m 0755 /opt/router/security"; \
	  scp -o StrictHostKeyChecking=accept-new home-secnet/tools/optional-security/*.sh $${ROUTER_ADMIN_USER}@$${ROUTER_IP}:/tmp/; \
	  ssh -o StrictHostKeyChecking=accept-new $${ROUTER_ADMIN_USER}@$${ROUTER_IP} "sudo mv /tmp/*.sh /opt/router/security/ && sudo chmod +x /opt/router/security/*.sh && sudo systemctl daemon-reload && sudo systemctl enable --now home-secnet-daily-update.timer home-secnet-daily-lynis.timer home-secnet-daily-rootkit.timer home-secnet-daily-malware.timer"; \
	  echo "[security] Enabled";'
