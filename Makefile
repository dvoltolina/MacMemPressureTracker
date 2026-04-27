# Makefile for memory-pressure-monitor
#
# Targets are intentionally simple wrappers; CI invokes the same commands.

SHELL := /bin/bash

SHFMT_FLAGS := -i 2 -ci -bn -sr

SHELL_FILES := $(shell find scripts lib tests -type f \( -name '*.sh' -o -name '*.bats' \) 2>/dev/null)

.PHONY: help
help:  ## Show this help.
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

.PHONY: dev-deps
dev-deps:  ## Install development dependencies via Homebrew.
	@command -v brew >/dev/null || { echo "Homebrew not found. Install from https://brew.sh"; exit 1; }
	brew install bats-core shellcheck shfmt

.PHONY: fmt
fmt:  ## Format shell files in place.
	@if ! command -v shfmt >/dev/null; then echo "shfmt not installed; run 'make dev-deps'"; exit 1; fi
	shfmt $(SHFMT_FLAGS) -w scripts lib tests

.PHONY: fmt-check
fmt-check:  ## Verify shell files are formatted.
	@if ! command -v shfmt >/dev/null; then echo "shfmt not installed; run 'make dev-deps'"; exit 1; fi
	shfmt $(SHFMT_FLAGS) -d scripts lib tests

.PHONY: lint
lint:  ## Run shellcheck over scripts and libraries.
	@if ! command -v shellcheck >/dev/null; then echo "shellcheck not installed; run 'make dev-deps'"; exit 1; fi
	@shopt -s nullglob; \
		files=(scripts/*.sh lib/*.sh); \
		if [ $${#files[@]} -eq 0 ]; then echo "no shell files yet; skipping shellcheck"; exit 0; fi; \
		shellcheck "$${files[@]}"

.PHONY: test
test:  ## Run the bats-core test suite.
	@if ! command -v bats >/dev/null; then echo "bats not installed; run 'make dev-deps'"; exit 1; fi
	bats tests

.PHONY: check
check: fmt-check lint test  ## Run formatter, linter, and tests (CI gate).

.PHONY: status
status:  ## Show launchd install/load status.
	./scripts/status.sh

.PHONY: install
install:  ## Install the launchd user agent.
	./scripts/install.sh

.PHONY: uninstall
uninstall:  ## Uninstall the launchd user agent.
	./scripts/uninstall.sh
