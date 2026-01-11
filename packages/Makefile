# Kustomize packages build system for idpbuilder
# Usage: make build-<environment>
# For full cluster management, use: source ../deployment/scripts/cluster-menu.sh

.PHONY: all clean build-kind build-kind-ryzen build-kind-thinkpad build-talos build-hub build-all
.PHONY: deploy-kind deploy-kind-ryzen deploy-kind-thinkpad
.PHONY: shell help validate-kind

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
	@echo "Build targets (generate packages only):"
	@echo "  build-kind          Build KIND local development environment"
	@echo "  build-kind-ryzen    Build KIND for Ryzen host"
	@echo "  build-kind-thinkpad Build KIND for Thinkpad host"
	@echo "  build-talos         Build Talos production environment"
	@echo "  build-hub           Build Hub multi-cluster environment"
	@echo "  build-all           Build all environments"
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
	@echo "  help                Show this help"
	@echo ""
	@echo "For full documentation, see README.md"
