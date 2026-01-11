#!/usr/bin/env bash
# Build script for kustomize packages
# Generates idpbuilder-compatible output structure

set -e

PACKAGES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${PACKAGES_DIR}/dist"
ENV="${1:-kind}"

echo "Building $ENV environment..."
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
        for comp in kind-only tailscale-serve observability; do
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
    [ -n "$(ls -A "$dir" 2>/dev/null)" ] || return

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
        for comp in kind-only tailscale-serve observability; do
            for dir in "${PACKAGES_DIR}/components/${comp}/manifests/"*/; do
                [ -d "$dir" ] || continue
                copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
            done
        done
        ;;
    talos|hub)
        for comp in talos-only tailscale-serve observability; do
            for dir in "${PACKAGES_DIR}/components/${comp}/manifests/"*/; do
                [ -d "$dir" ] || continue
                copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
            done
        done
        ;;
esac

# Count results
app_count=$(ls -1 "${DIST_DIR}/${ENV}"/*.yaml 2>/dev/null | wc -l)
manifest_dirs=$(find "${DIST_DIR}/${ENV}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

echo "Built ${ENV} environment:"
echo "  - ${app_count} ArgoCD Applications"
echo "  - ${manifest_dirs} manifest directories"
echo "  - Output: ${DIST_DIR}/${ENV}/"
