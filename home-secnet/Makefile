SHELL := /bin/bash
.DEFAULT_GOAL := help

help:
	@echo "Targets: all | router | checks | clean"

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
	bash tests/verify_wg.sh || true
	bash tests/verify_dns.sh || true
	bash tests/verify_isolation.sh || true
	bash tests/verify_ids.sh || true
	bash tests/verify_spa.sh || true

clean:
	rm -rf render/ clients/
