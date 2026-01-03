#!/usr/bin/env bash
# nixidy-to-idpbuilder.sh
# Restructure nixidy output to idpBuilder-compatible format
# Part of: Feature 114 - nixidy migration
#
# nixidy outputs: result/<app>/<Kind>-<name>.yaml (flat files)
# idpBuilder expects: dist/<app>.yaml (ArgoCD App) + dist/<app>/manifests/*.yaml
#
# Usage:
#   ./scripts/nixidy-to-idpbuilder.sh [--env ENV_TYPE] [--output DIR] [--dry-run]
#
# Options:
#   --env ENV_TYPE   Environment type: kind, talos, hub (default: kind)
#   --output DIR     Output directory (default: dist)
#   --dry-run        Show what would be done without making changes
#   --help           Show this help message

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENV_TYPE="kind"
OUTPUT_DIR="dist"
DRY_RUN=false

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NIXIDY_DIR="${REPO_ROOT}/nixidy"

# Help function
show_help() {
    head -18 "$0" | tail -16 | sed 's/^# //'
    exit 0
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV_TYPE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate environment type
if [[ ! "$ENV_TYPE" =~ ^(kind|talos|hub)$ ]]; then
    log_error "Invalid environment type: $ENV_TYPE (must be kind, talos, or hub)"
    exit 1
fi

# Build nixidy manifests
build_nixidy() {
    log_info "Building nixidy manifests for ${ENV_TYPE}..."

    cd "${NIXIDY_DIR}"

    # Build using nixidy
    if nix build ".#nixidyEnvs.x86_64-linux.${ENV_TYPE}.config.build" 2>&1; then
        log_success "nixidy build completed"
    else
        log_error "nixidy build failed"
        return 1
    fi

    cd "${REPO_ROOT}"
}

# Get the nixidy result path
get_nixidy_result() {
    local result_path="${NIXIDY_DIR}/result"

    if [[ ! -L "$result_path" ]] && [[ ! -d "$result_path" ]]; then
        log_error "nixidy result not found at ${result_path}. Run build first."
        exit 1
    fi

    # Handle both old format (result/<app>/) and new activation package format (result/environment/<app>/)
    if [[ -d "${result_path}/environment" ]]; then
        echo "${result_path}/environment"
    else
        echo "$result_path"
    fi
}

# Restructure nixidy output to idpBuilder format
restructure_output() {
    local nixidy_result
    nixidy_result=$(get_nixidy_result)

    log_info "Restructuring nixidy output to idpBuilder format..."
    log_info "Source: ${nixidy_result}"
    log_info "Target: ${OUTPUT_DIR}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN - no changes will be made"
    fi

    # Clean output directory
    if [[ "$DRY_RUN" == "false" ]]; then
        # Make files writable before removal (nix store files are read-only)
        if [[ -d "${OUTPUT_DIR}" ]]; then
            chmod -R u+w "${OUTPUT_DIR}" 2>/dev/null || true
        fi
        rm -rf "${OUTPUT_DIR}"
        mkdir -p "${OUTPUT_DIR}"
    fi

    # Find all app directories (excluding 'apps' which contains ArgoCD Applications)
    for app_dir in "${nixidy_result}"/*; do
        if [[ ! -d "$app_dir" ]]; then
            continue
        fi

        local app_name=$(basename "$app_dir")

        # Skip the 'apps' directory - this contains ArgoCD Application definitions
        if [[ "$app_name" == "apps" ]]; then
            process_argocd_apps "$app_dir"
            continue
        fi

        log_info "Processing app: ${app_name}"

        local target_manifest_dir="${OUTPUT_DIR}/${app_name}/manifests"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would create: ${target_manifest_dir}/"
            for yaml_file in "${app_dir}"/*.yaml; do
                if [[ -f "$yaml_file" ]]; then
                    echo "  Would copy: $(basename "$yaml_file")"
                fi
            done
        else
            mkdir -p "$target_manifest_dir"

            # Copy all YAML files to manifests directory
            for yaml_file in "${app_dir}"/*.yaml; do
                if [[ -f "$yaml_file" ]]; then
                    cp "$yaml_file" "$target_manifest_dir/"
                fi
            done

            # Ensure files are writable (nix store files are read-only)
            chmod -R u+w "$target_manifest_dir/" 2>/dev/null || true

            log_success "  Created: ${target_manifest_dir}/"
        fi
    done
}

# Process ArgoCD Application definitions from the 'apps' directory
process_argocd_apps() {
    local apps_dir="$1"

    log_info "Processing ArgoCD Applications from 'apps' directory..."

    for app_file in "${apps_dir}"/*.yaml; do
        if [[ ! -f "$app_file" ]]; then
            continue
        fi

        local filename=$(basename "$app_file")
        # Remove 'Application-' prefix if present
        local app_name="${filename#Application-}"
        app_name="${app_name%.yaml}"

        log_info "Processing ArgoCD Application: ${app_name}"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would create: ${OUTPUT_DIR}/${app_name}.yaml"
        else
            # For idpBuilder, we need to adjust the source URLs
            # Replace GitHub URLs with cnoe:// protocol for KIND
            if [[ "$ENV_TYPE" == "kind" ]]; then
                # Transform GitHub source to cnoe:// protocol using sed
                # This avoids yq version compatibility issues
                # Keep path: . for ArgoCD to find manifests in the repo root
                sed -e "s|repoURL:.*|repoURL: cnoe://${app_name}/manifests|" \
                    -e "s|path:.*|path: .|" \
                    -e '/targetRevision:/d' \
                    "$app_file" > "${OUTPUT_DIR}/${app_name}.yaml"
            else
                # For Talos/Hub, keep the GitHub source as-is
                cp "$app_file" "${OUTPUT_DIR}/${app_name}.yaml"
            fi

            # Ensure file is writable (nix store files are read-only)
            chmod u+w "${OUTPUT_DIR}/${app_name}.yaml" 2>/dev/null || true

            log_success "  Created: ${OUTPUT_DIR}/${app_name}.yaml"
        fi
    done
}

# Handle file-based templates (templates with skeleton directories)
# These need the full directory structure, not flat manifests
handle_file_based_templates() {
    log_info "Processing file-based templates..."

    # Backstage templates - need full directory structure with skeletons
    local backstage_templates="${REPO_ROOT}/nixidy/templates/backstage"
    if [[ -d "$backstage_templates" ]]; then
        local target_dir="${OUTPUT_DIR}/backstage-templates/entities"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would remove: ${OUTPUT_DIR}/backstage-templates/manifests"
            echo "  Would copy: ${backstage_templates} -> ${target_dir}"
        else
            # Remove nixidy-generated flat manifests
            rm -rf "${OUTPUT_DIR}/backstage-templates/manifests"

            # Copy the full template directory tree
            mkdir -p "${OUTPUT_DIR}/backstage-templates"
            cp -r "$backstage_templates" "$target_dir"

            # Ensure files are writable
            chmod -R u+w "$target_dir" 2>/dev/null || true

            # Update the ArgoCD Application to use entities path and exclude catalog-info.yaml
            local app_yaml="${OUTPUT_DIR}/backstage-templates.yaml"
            if [[ -f "$app_yaml" ]]; then
                # Update repoURL to use /entities instead of /manifests
                sed -i 's|cnoe://backstage-templates/manifests|cnoe://backstage-templates/entities|' "$app_yaml"

                # Add directory exclude for catalog-info.yaml (Backstage catalog file, not K8s resource)
                # Insert after path: . line
                if ! grep -q "directory:" "$app_yaml"; then
                    sed -i '/path: \./a\    directory:\n      exclude: '\''catalog-info.yaml'\''' "$app_yaml"
                fi
            fi

            log_success "  backstage-templates: copied file-based templates with skeletons"
        fi
    else
        log_warning "  Backstage templates not found at ${backstage_templates}"
    fi
}

# Verify the restructured output
verify_output() {
    log_info "Verifying restructured output..."

    local app_count=0
    local manifest_count=0

    for app_yaml in "${OUTPUT_DIR}"/*.yaml; do
        if [[ -f "$app_yaml" ]]; then
            ((app_count++)) || true

            local app_name=$(basename "$app_yaml" .yaml)
            local manifest_dir="${OUTPUT_DIR}/${app_name}/manifests"

            if [[ -d "$manifest_dir" ]]; then
                local manifests=$(ls "${manifest_dir}"/*.yaml 2>/dev/null | wc -l)
                ((manifest_count += manifests)) || true
                log_success "  ${app_name}: ${manifests} manifests"
            else
                log_warning "  ${app_name}: No manifests directory"
            fi
        fi
    done

    echo ""
    log_info "========================================="
    log_info "Restructuring Complete"
    log_info "========================================="
    log_success "ArgoCD Applications: ${app_count}"
    log_success "Total Manifests: ${manifest_count}"
    log_info "Output directory: ${OUTPUT_DIR}"
}

# Main execution
main() {
    log_info "Starting nixidy to idpBuilder restructuring"
    log_info "Environment: ${ENV_TYPE}"

    # Build if result doesn't exist
    if [[ ! -e "${NIXIDY_DIR}/result" ]]; then
        build_nixidy
    fi

    # Restructure output
    restructure_output

    # Handle file-based templates (Backstage templates with skeletons)
    handle_file_based_templates

    # Verify if not dry run
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_output
    fi

    log_success "Done! Output ready for idpBuilder at: ${OUTPUT_DIR}/"
}

main "$@"
