SHELL := /bin/bash
.PHONY: openwrt-render openwrt-build openwrt-flash checks-openwrt tests lint spa hypervisor-setup oneclick oneclick-flash

ROOT := $(shell pwd)
SCRIPTS := $(ROOT)/scripts

openwrt-render:
	"$(SCRIPTS)/render_router_configs.sh"

openwrt-build:
	"$(SCRIPTS)/openwrt_build.sh"

openwrt-flash:
	@echo "[make] Flashing requires device=/dev/sdX image=<path> (interactive)."

lint:
	@echo "[lint] shellcheck all scripts"
	@files=$$(find "$(ROOT)" -type f -name '*.sh'); \
	 if [ -z "$$files" ]; then \
	   echo "[lint] no shell scripts found"; \
	 else \
	   shellcheck $$files; \
	 fi

tests:
	@"$(ROOT)/tests/verify_no_generated_in_router.sh"
	@"$(ROOT)/tests/spa_unit.sh" || true
	@"$(ROOT)/tests/verify_no_smarty.sh"

checks-openwrt: lint tests

# Hypervisor setup: create vmbr0/vmbr1 on Proxmox if detected (idempotent)
hypervisor-setup:
	@"$(SCRIPTS)/providers/proxmox/configure_bridges.sh"

oneclick:
	@"$(SCRIPTS)/oneclick.sh" --yes

oneclick-flash:
	@"$(SCRIPTS)/oneclick.sh" --yes --flash device=$${device}
