SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: all spa router checks clean help

help:
	@echo "Targets: all | router | checks | clean"
	@echo "Dev: fmt | clippy"

all: spa
	bash scripts/preflight.sh
	bash scripts/setup_env.sh
	bash scripts/detect_nics.sh
	bash scripts/harden_host.sh
	bash scripts/configure_bridges.sh
	bash scripts/prepare_cloud_image.sh
	bash scripts/create_router_vm.sh
	bash scripts/render_router_configs.sh
	bash scripts/apply_router_configs.sh
	bash scripts/apply_node_firewall.sh
	bash scripts/setup_security_maintenance.sh || true
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
	bash scripts/configure_bridges.sh
	bash scripts/prepare_cloud_image.sh
	bash scripts/create_router_vm.sh
	bash scripts/render_router_configs.sh
	bash scripts/apply_router_configs.sh

checks:
	bash tests/verify_wg.sh 
	bash tests/verify_dns.sh 
	bash tests/verify_isolation.sh 
	bash tests/verify_ids.sh 
	bash tests/verify_spa.sh 

clean:
	rm -rf render/ clients/

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
