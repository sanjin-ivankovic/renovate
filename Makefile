# ============================================================================
# example-org/renovate — central Renovate runner + shared preset
# ============================================================================
#
# Usage:
#   make help        - Show this help
#   make setup       - Install pre-commit hooks
#   make validate    - Validate the Renovate presets (renovate-config-validator)
#
# ============================================================================

.PHONY: help setup validate
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "example-org/renovate - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'
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
	npx --yes --package "renovate@$$ENGINE" renovate-config-validator --strict \
		default.json dockerfile-args.json ci-components.json renovate.json
	@echo "✅ Renovate config valid"
