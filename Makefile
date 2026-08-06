# vivado-container-suite
#
#   make help          list targets
#   make check         everything CI runs, minus the container build
#
# All development tooling is pinned (scripts/tools.lock) and fetched into
# .tools/ -- nothing is installed system-wide.

SHELL      := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

TOOLS      := .tools
BATS       := $(TOOLS)/bin/bats
SHELLCHECK := $(TOOLS)/bin/shellcheck
HADOLINT   := $(TOOLS)/bin/hadolint

SH_SOURCES := bin/vvd $(wildcard lib/*.sh) $(wildcard lib/cmd/*.sh) \
              $(wildcard scripts/*.sh) $(wildcard docker/*.sh) \
              $(wildcard container/*.sh) test/helper.bash test/fixtures/bin/docker

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "targets:\n"} \
	     /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: tools
tools: ## Fetch the pinned development tooling into .tools/
	@./scripts/fetch-tools.sh

$(BATS) $(SHELLCHECK) $(HADOLINT):
	@./scripts/fetch-tools.sh

.PHONY: check
check: pinning lint test ## Lint, verify pinning and run the unit tests

.PHONY: lint
lint: shellcheck hadolint tcllint ## Run every linter

.PHONY: shellcheck
shellcheck: $(SHELLCHECK) ## Lint the shell sources
	@$(SHELLCHECK) -x -s bash $(SH_SOURCES)
	@$(SHELLCHECK) docker/profile.sh
	@echo "shellcheck: clean"

.PHONY: hadolint
hadolint: $(HADOLINT) ## Lint the Dockerfile
	@$(HADOLINT) docker/Dockerfile
	@echo "hadolint: clean"

.PHONY: tcllint
tcllint: ## Syntax-check the Tcl layer (needs tclsh, or the built image)
	@./scripts/tcl-syntax.sh

.PHONY: test
test: $(BATS) ## Run the bats unit tests
	@$(BATS) test/

.PHONY: pinning
pinning: ## Verify every dependency is digest/SHA pinned
	@./scripts/verify-pinning.sh

.PHONY: lock
lock: ## Re-resolve every lock file (needs network)
	@./scripts/lock-images.sh
	@./scripts/lock-apt.sh

.PHONY: lock-check
lock-check: ## Fail if a lock file is stale
	@./scripts/lock-images.sh --check
	@./scripts/lock-apt.sh --check

.PHONY: image
image: ## Build the base container image
	@./bin/vvd build

.PHONY: selftest
selftest: ## Run the in-container availability tests
	@./bin/vvd selftest

.PHONY: example
example: ## Simulate the bundled example design
	@./bin/vvd -C examples/blinky sim

.PHONY: clean
clean: ## Remove build output and fetched tooling
	@rm -rf $(TOOLS) examples/blinky/build
	@echo "cleaned"
