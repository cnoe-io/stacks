#!/usr/bin/env bash
# Build script for kustomize packages
# Generates idpbuilder-compatible output structure

set -e

PACKAGES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${PACKAGES_DIR}/dist"
ENV="${1:-kind}"

# Determine host-specific values for envsubst substitution
case "$ENV" in
    kind-ryzen)
        export TAILSCALE_HOST="ryzen"
        ;;
    kind-thinkpad)
        export TAILSCALE_HOST="thinkpad"
        ;;
    kind)
        export TAILSCALE_HOST="localdev"
        ;;
    talos)
        export TAILSCALE_HOST="talos"
        ;;
    hub)
        export TAILSCALE_HOST="hub"
        ;;
    *)
        export TAILSCALE_HOST="localdev"
        ;;
esac
export TAILSCALE_TAILNET="tail286401.ts.net"

echo "Building $ENV environment (TAILSCALE_HOST=${TAILSCALE_HOST})..."

# Step 0: Generate Kargo inner-loop pipelines from config
KARGO_GENERATOR="${PACKAGES_DIR}/scripts/generate-kargo-pipelines.sh"
if [ -f "$KARGO_GENERATOR" ]; then
    echo ""
    "$KARGO_GENERATOR"
    echo ""
fi

mkdir -p "${DIST_DIR}/${ENV}"

# Clean previous build
rm -rf "${DIST_DIR}/${ENV}"/*

# Step 1: Copy all Application YAMLs, renaming to simple names
# From base/apps/
for f in "${PACKAGES_DIR}/base/apps/"*.yaml; do
    [ -f "$f" ] || continue
    app=$(basename "$f")
    cp "$f" "${DIST_DIR}/${ENV}/${app}"
done

# From components (based on environment)
case "$ENV" in
    kind|kind-*)
        for comp in active-development kind-only tailscale-serve observability; do
            for f in "${PACKAGES_DIR}/components/${comp}/apps/"*.yaml; do
                [ -f "$f" ] || continue
                app=$(basename "$f")
                cp "$f" "${DIST_DIR}/${ENV}/${app}"
            done
        done
        ;;
    talos)
        for comp in talos-only tailscale-serve observability; do
            for f in "${PACKAGES_DIR}/components/${comp}/apps/"*.yaml; do
                [ -f "$f" ] || continue
                app=$(basename "$f")
                cp "$f" "${DIST_DIR}/${ENV}/${app}"
            done
        done
        ;;
    hub)
        for comp in talos-only tailscale-serve observability; do
            for f in "${PACKAGES_DIR}/components/${comp}/apps/"*.yaml; do
                [ -f "$f" ] || continue
                app=$(basename "$f")
                cp "$f" "${DIST_DIR}/${ENV}/${app}"
            done
        done
        ;;
esac

# Step 2: Copy manifests to match Application structure
# idpbuilder expects: <app>.yaml + <app>/<subdir>/*.yaml
# Standard pattern: cnoe://<app>/manifests -> <app>/manifests/
# Special case: cnoe://<app>/entities -> <app>/entities/ (backstage-templates)

# Helper function to copy manifest directory
copy_manifest_dir() {
    local dir="$1"
    local dest_base="$2"
    local app=$(basename "$dir")

    # Skip empty directories
    [ -n "$(ls -A "$dir" 2>/dev/null)" ] || return 0

    # Check if directory has subdirectories (like entities/)
    if [ -d "$dir/entities" ]; then
        # Copy entities subdirectory structure
        mkdir -p "${dest_base}/${app}/entities"
        cp -r "$dir/entities/"* "${dest_base}/${app}/entities/" 2>/dev/null || true
    elif [ -d "$dir/manifests" ]; then
        # Copy manifests subdirectory if it exists
        mkdir -p "${dest_base}/${app}/manifests"
        cp -r "$dir/manifests/"* "${dest_base}/${app}/manifests/" 2>/dev/null || true
    else
        # Copy YAML files directly to manifests/
        mkdir -p "${dest_base}/${app}/manifests"
        cp "$dir"/*.yaml "${dest_base}/${app}/manifests/" 2>/dev/null || true
    fi
}

# From base/manifests/
for dir in "${PACKAGES_DIR}/base/manifests/"*/; do
    [ -d "$dir" ] || continue
    copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
done

# From components (based on environment)
case "$ENV" in
    kind|kind-*)
        for comp in active-development kind-only tailscale-serve observability; do
            for dir in "${PACKAGES_DIR}/components/${comp}/manifests/"*/; do
                [ -d "$dir" ] || continue
                copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
            done
        done
        ;;
    talos)
        for comp in talos-only tailscale-serve observability; do
            for dir in "${PACKAGES_DIR}/components/${comp}/manifests/"*/; do
                [ -d "$dir" ] || continue
                copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
            done
        done
        ;;
    hub)
        for comp in talos-only tailscale-serve observability; do
            for dir in "${PACKAGES_DIR}/components/${comp}/manifests/"*/; do
                [ -d "$dir" ] || continue
                copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
            done
        done
        ;;
esac

# Step 3: Substitute host-specific values in all YAML files
# This replaces ${TAILSCALE_HOST} and ${TAILSCALE_TAILNET} placeholders using sed
echo "Substituting host-specific values..."
find "${DIST_DIR}/${ENV}" -name "*.yaml" -type f | while read -r file; do
    sed -i "s/\${TAILSCALE_HOST}/${TAILSCALE_HOST}/g; s/\${TAILSCALE_TAILNET}/${TAILSCALE_TAILNET}/g" "$file"
    if [ -n "${AZURE_STORAGE_ACCOUNT:-}" ]; then
        sed -i "s/\${AZURE_STORAGE_ACCOUNT}/${AZURE_STORAGE_ACCOUNT}/g" "$file"
    fi
    if [ -n "${AZURE_CLIENT_ID:-}" ]; then
        sed -i "s/\${AZURE_CLIENT_ID}/${AZURE_CLIENT_ID}/g" "$file"
    fi
    if [ -n "${AZURE_TENANT_ID:-}" ]; then
        sed -i "s/\${AZURE_TENANT_ID}/${AZURE_TENANT_ID}/g" "$file"
    fi
    if [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
        sed -i "s/\${AZURE_SUBSCRIPTION_ID}/${AZURE_SUBSCRIPTION_ID}/g" "$file"
    fi
    if [ -n "${RESOURCE_GROUP:-}" ]; then
        sed -i "s/\${RESOURCE_GROUP}/${RESOURCE_GROUP}/g" "$file"
    fi
done

# Step 4: Remove orphaned manifest directories (no matching Application YAML)
for dir in "${DIST_DIR}/${ENV}"/*/; do
    [ -d "$dir" ] || continue
    app=$(basename "$dir")
    if [ ! -f "${DIST_DIR}/${ENV}/${app}.yaml" ]; then
        rm -rf "$dir"
    fi
done

# Count results
app_count=$(ls -1 "${DIST_DIR}/${ENV}"/*.yaml 2>/dev/null | wc -l)
manifest_dirs=$(find "${DIST_DIR}/${ENV}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

echo "Built ${ENV} environment:"
echo "  - ${app_count} ArgoCD Applications"
echo "  - ${manifest_dirs} manifest directories"
echo "  - Output: ${DIST_DIR}/${ENV}/"
