# Kustomize packages build system for idpbuilder
# Usage: make build-<environment>
# For full cluster management, use: source ../deployment/scripts/cluster-menu.sh

.PHONY: all clean build-kind build-kind-ryzen build-kind-thinkpad build-talos build-hub build-all
.PHONY: build-kustomize-kind build-kustomize-kind-ryzen build-kustomize-kind-thinkpad build-kustomize-talos build-kustomize-hub build-kustomize-all
.PHONY: deploy-kind deploy-kind-ryzen deploy-kind-thinkpad
.PHONY: shell help validate-kind compare-builds

all: build-kind

# ═══════════════════════════════════════════════════════════════════════════════
# Build targets - generate idpbuilder-compatible package structure
# ═══════════════════════════════════════════════════════════════════════════════

build-kind:
	@./scripts/build.sh kind

build-kind-ryzen:
	@./scripts/build.sh kind-ryzen

build-kind-thinkpad:
	@./scripts/build.sh kind-thinkpad

build-talos:
	@./scripts/build.sh talos

build-hub:
	@./scripts/build.sh hub

build-all: build-kind build-kind-ryzen build-kind-thinkpad build-talos build-hub

# ═══════════════════════════════════════════════════════════════════════════════
# Kustomize build targets - native kustomize + yq splitting
# These use proper kustomize composition for Applications
# ═══════════════════════════════════════════════════════════════════════════════

build-kustomize-kind:
	@./scripts/build-kustomize.sh kind

build-kustomize-kind-ryzen:
	@./scripts/build-kustomize.sh kind-ryzen

build-kustomize-kind-thinkpad:
	@./scripts/build-kustomize.sh kind-thinkpad

build-kustomize-talos:
	@./scripts/build-kustomize.sh talos

build-kustomize-hub:
	@./scripts/build-kustomize.sh hub

build-kustomize-all: build-kustomize-kind build-kustomize-kind-ryzen build-kustomize-kind-thinkpad build-kustomize-talos build-kustomize-hub

# Compare legacy and kustomize builds
compare-builds:
	@echo "Building with legacy build.sh..."
	@./scripts/build.sh kind-ryzen
	@mv dist/kind-ryzen dist/kind-ryzen-legacy
	@echo ""
	@echo "Building with build-kustomize.sh..."
	@./scripts/build-kustomize.sh kind-ryzen
	@echo ""
	@echo "Comparing outputs..."
	@echo "Legacy apps: $$(ls -1 dist/kind-ryzen-legacy/*.yaml 2>/dev/null | wc -l)"
	@echo "Kustomize apps: $$(ls -1 dist/kind-ryzen/*.yaml 2>/dev/null | wc -l)"
	@echo ""
	@echo "Diff (files only in legacy):"
	@diff -rq dist/kind-ryzen-legacy dist/kind-ryzen 2>/dev/null | grep "Only in dist/kind-ryzen-legacy" | head -10 || echo "  (none)"
	@echo ""
	@echo "Diff (files only in kustomize):"
	@diff -rq dist/kind-ryzen-legacy dist/kind-ryzen 2>/dev/null | grep "Only in dist/kind-ryzen" | head -10 || echo "  (none)"
	@rm -rf dist/kind-ryzen-legacy

# ═══════════════════════════════════════════════════════════════════════════════
# Simple deploy targets - idpbuilder only, no Azure integration
# For full deployment with Azure WI, TLS, JWKS, use deployment/scripts/cluster-menu.sh
# ═══════════════════════════════════════════════════════════════════════════════

deploy-kind: build-kind
	idpbuilder create --package dist/kind/

deploy-kind-ryzen: build-kind-ryzen
	idpbuilder create --package dist/kind-ryzen/

deploy-kind-thinkpad: build-kind-thinkpad
	idpbuilder create --package dist/kind-thinkpad/

# ═══════════════════════════════════════════════════════════════════════════════
# Cluster management (use deployment/scripts/cluster-menu.sh)
# ═══════════════════════════════════════════════════════════════════════════════

# Interactive cluster management shell
shell:
	@echo "Source the cluster management script in your shell:"
	@echo ""
	@echo "  source \$$(dirname $(PWD))/deployment/scripts/cluster-menu.sh"
	@echo ""
	@echo "Available commands after sourcing:"
	@echo "  cluster-deploy (cld)   - Full cluster creation with Azure integration"
	@echo "  cluster-update (clu)   - Update cluster after manifest edits"
	@echo "  cluster-recreate (clr) - Delete and recreate cluster"
	@echo "  cluster-build (clb)    - Build kustomize packages only"
	@echo "  cluster-status (clst)  - Show cluster status"
	@echo "  cluster-menu (clm)     - Interactive menu (requires gum)"

# ═══════════════════════════════════════════════════════════════════════════════
# Utility targets
# ═══════════════════════════════════════════════════════════════════════════════

# Clean generated files
clean:
	rm -rf dist/*

# Validation
validate-kind:
	@echo "Validating KIND build..."
	@ls dist/kind/*.yaml 2>/dev/null | wc -l | xargs -I{} echo "Applications: {}"
	@find dist/kind -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | xargs -I{} echo "Manifest dirs: {}"

# ═══════════════════════════════════════════════════════════════════════════════
# Help
# ═══════════════════════════════════════════════════════════════════════════════

help:
	@echo "Kustomize Packages Build System"
	@echo ""
	@echo "For full cluster management with Azure integration, use:"
	@echo "  source ../deployment/scripts/cluster-menu.sh"
	@echo "  cluster-deploy   # or: cld"
	@echo ""
	@echo "Build targets (legacy - manual file copying):"
	@echo "  build-kind          Build KIND local development environment"
	@echo "  build-kind-ryzen    Build KIND for Ryzen host"
	@echo "  build-kind-thinkpad Build KIND for Thinkpad host"
	@echo "  build-talos         Build Talos production environment"
	@echo "  build-hub           Build Hub multi-cluster environment"
	@echo "  build-all           Build all environments"
	@echo ""
	@echo "Kustomize build targets (native kustomize + yq splitting):"
	@echo "  build-kustomize-kind          Build KIND via kustomize"
	@echo "  build-kustomize-kind-ryzen    Build KIND-Ryzen via kustomize"
	@echo "  build-kustomize-kind-thinkpad Build KIND-Thinkpad via kustomize"
	@echo "  build-kustomize-talos         Build Talos via kustomize"
	@echo "  build-kustomize-hub           Build Hub via kustomize"
	@echo "  build-kustomize-all           Build all via kustomize"
	@echo ""
	@echo "Simple deploy targets (idpbuilder only, no Azure integration):"
	@echo "  deploy-kind         Build and deploy KIND via idpbuilder"
	@echo "  deploy-kind-ryzen   Build and deploy KIND-Ryzen via idpbuilder"
	@echo "  deploy-kind-thinkpad Build and deploy KIND-Thinkpad via idpbuilder"
	@echo ""
	@echo "Utility:"
	@echo "  shell               Show how to source cluster-menu.sh"
	@echo "  clean               Remove generated files"
	@echo "  validate-kind       Validate KIND build output"
	@echo "  compare-builds      Compare legacy vs kustomize build outputs"
	@echo "  help                Show this help"
	@echo ""
	@echo "For full documentation, see README.md"
