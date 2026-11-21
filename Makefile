# ============================================================================
# example-org/renovate — central Renovate runner + shared preset
# ============================================================================
#
# Usage:
#   make help        - Show this help
#   make setup       - Install pre-commit hooks
#   make validate    - Validate the Renovate presets (renovate-config-validator)
#   make lanes       - Lane report of repos as they are on GitLab (REPOS=...)
#   make lanes-local - Lane report of a working tree with these presets (DIR=...)
#
# ============================================================================

.PHONY: help setup validate lanes lanes-local
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "example-org/renovate - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-13s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Install pre-commit hooks (run once after cloning)
	@echo "Installing pre-commit hooks..."
	@pre-commit install
	@pre-commit install --hook-type commit-msg
	@echo "Done. Pre-commit hooks are now active."

validate: ## Validate all Renovate presets (same engine major, files and strictness as CI)
	@echo "Validating Renovate config..."
	@ENGINE=$$(sed -n 's/.*renovatebot\/renovate:\([0-9]*\).*/\1/p' .gitlab-ci.yml | head -1); \
	echo "Using renovate@$$ENGINE (from CI_RENOVATE_IMAGE)"; \
	npx --yes --package "renovate@$$ENGINE" renovate-config-validator --strict *.json
	@echo "✅ Renovate config valid"

# Engine version from CI_RENOVATE_IMAGE (exact tag), so the dry run resolves
# rules the way the runner does. Output goes to .cache/lanes/ (git-ignored).
ENGINE_FULL = $(shell sed -n 's/.*renovatebot\/renovate:\([0-9.]*\).*/\1/p' .gitlab-ci.yml | head -1)
LANES_OUT ?= .cache/lanes

lanes: ## Lane report of repos as they are on GitLab: make lanes REPOS="homelab/argo-apps homelab/helm-charts"
	@test -n "$(REPOS)" || { echo 'usage: make lanes REPOS="homelab/<repo> ..."'; exit 2; }
	@npx --yes --package "renovate@$(ENGINE_FULL)" -c 'scripts/dry-run.sh gitlab "$(LANES_OUT)" $(REPOS)'

lanes-local: ## Lane report of a working tree against this checkout's presets: make lanes-local DIR=../argo-apps
	@test -n "$(DIR)" || { echo 'usage: make lanes-local DIR=../<repo>'; exit 2; }
	@npx --yes --package "renovate@$(ENGINE_FULL)" -c 'scripts/dry-run.sh local "$(LANES_OUT)" "$(DIR)"'
