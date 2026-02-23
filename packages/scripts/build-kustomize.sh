#!/usr/bin/env bash
# Build script using native kustomize for Application composition
# Generates idpbuilder-compatible output structure
#
# Benefits over build.sh:
# - Uses kustomize for proper component composition
# - configMapGenerator produces cluster-config
# - Overlay inheritance works (kind-ryzen extends kind)
# - Future: can add patches, replacements

set -e

PACKAGES_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check for yq-go (mikefarah/yq), required for YAML splitting
check_yq() {
    local yq_version
    yq_version=$(yq --version 2>&1 || true)
    if [[ "$yq_version" == *"mikefarah"* ]] || [[ "$yq_version" == *"https://github.com/mikefarah/yq"* ]]; then
        return 0  # yq-go is available
    else
        echo "Error: yq-go (mikefarah/yq) is required but not found."
        echo "Found: $yq_version"
        echo ""
        echo "Run this script inside devenv shell, or install yq-go:"
        echo "  nix-shell -p yq-go --run '$0 $*'"
        exit 1
    fi
}

check_yq
DIST_DIR="${PACKAGES_DIR}/dist"
ENV="${1:-kind}"

# Determine host-specific values for substitution
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

# Clean and create output directory
rm -rf "${DIST_DIR}/${ENV}"
mkdir -p "${DIST_DIR}/${ENV}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Build Applications via kustomize and split into individual files
# ═══════════════════════════════════════════════════════════════════════════════
echo "Step 1: Building Applications via kustomize..."

# Create temp directory for yq output (yq -s writes to current directory)
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"

# Build kustomize overlay and split by metadata.name
# yq-go splits multi-doc YAML into separate files named by expression result
kubectl kustomize "${PACKAGES_DIR}/overlays/${ENV}" | yq -s '.metadata.name' -o yaml --no-doc

# Process split files - move Applications to dist, skip others (like ConfigMaps)
for f in *.yml; do
    [ -f "$f" ] || continue
    app="${f%.yml}"

    # Get the kind field to filter
    kind=$(yq '.kind' "$f" 2>/dev/null)

    # Only keep Application resources
    if [[ "$kind" == "Application" ]]; then
        mv "$f" "${DIST_DIR}/${ENV}/${app}.yaml"
    else
        # Skip ConfigMaps and other non-Application resources
        rm "$f"
    fi
done

cd "${PACKAGES_DIR}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Copy manifests to match Application structure
# idpbuilder expects: <app>.yaml + <app>/<subdir>/*.yaml
# Standard pattern: cnoe://<app>/manifests -> <app>/manifests/
# Special case: cnoe://<app>/entities -> <app>/entities/ (backstage-templates)
# ═══════════════════════════════════════════════════════════════════════════════
echo "Step 2: Copying manifests..."

# Helper function to copy manifest directory
# If the directory uses kustomize components, render them to self-contained manifests
copy_manifest_dir() {
    local dir="$1"
    local dest_base="$2"
    local app=$(basename "$dir")

    # Skip empty directories
    # Important: returning non-zero here will abort the whole build because the
    # script runs with `set -e`.
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
        # Check if kustomization uses components (need to render instead of copy)
        if [ -f "$dir/kustomization.yaml" ] && grep -q "^components:" "$dir/kustomization.yaml" 2>/dev/null; then
            # Render kustomization with components and split into individual files
            render_kustomize_dir "$dir" "${dest_base}/${app}/manifests"
        else
            # Copy YAML files directly to manifests/
            mkdir -p "${dest_base}/${app}/manifests"
            cp "$dir"/*.yaml "${dest_base}/${app}/manifests/" 2>/dev/null || true
        fi
    fi
}

# Helper function to render a kustomization with components into self-contained manifests
render_kustomize_dir() {
    local src_dir="$1"
    local dest_dir="$2"
    local app=$(basename "$(dirname "$dest_dir")")

    echo "   Rendering kustomize components for: $app"
    mkdir -p "$dest_dir"

    # Render kustomization and split by Kind-Name
    local render_temp=$(mktemp -d)
    cd "$render_temp"

    if kubectl kustomize "$src_dir" 2>/dev/null | yq -s '.kind + "-" + .metadata.name' -o yaml --no-doc; then
        # Rename .yml to .yaml and move to destination
        for f in *.yml; do
            [ -f "$f" ] || continue
            mv "$f" "${dest_dir}/${f%.yml}.yaml"
        done

        # Generate self-contained kustomization.yaml
        generate_kustomization "$dest_dir"
    else
        echo "   Warning: Failed to render $app, falling back to copy"
        cd "${PACKAGES_DIR}"
        rm -rf "$render_temp"
        mkdir -p "$dest_dir"
        cp "$src_dir"/*.yaml "$dest_dir/" 2>/dev/null || true
        return
    fi

    cd "${PACKAGES_DIR}"
    rm -rf "$render_temp"
}

# Generate a self-contained kustomization.yaml from rendered files
generate_kustomization() {
    local dir="$1"
    local kustomization_file="$dir/kustomization.yaml"

    # Get list of YAML files (excluding kustomization.yaml itself)
    local resources=""
    for f in "$dir"/*.yaml; do
        [ -f "$f" ] || continue
        local basename=$(basename "$f")
        [ "$basename" = "kustomization.yaml" ] && continue
        resources="${resources}  - ${basename}\n"
    done

    # Write kustomization.yaml
    cat > "$kustomization_file" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
$(echo -e "$resources")
EOF
}

# From base/manifests/
for dir in "${PACKAGES_DIR}/base/manifests/"*/; do
    [ -d "$dir" ] || continue
    copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
done

# From all components: copy every available manifest directory, then prune
# against generated Application files in Step 5. This keeps build logic aligned
# with overlay composition without hard-coding component lists.
for comp_dir in "${PACKAGES_DIR}/components/"*/; do
    [ -d "$comp_dir" ] || continue
    for dir in "${comp_dir}manifests/"*/; do
        [ -d "$dir" ] || continue
        copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
    done
done

# From overlay-specific manifests (optional)
# These override base/component manifests for a specific environment.
if [ -d "${PACKAGES_DIR}/overlays/${ENV}/manifests" ]; then
    for dir in "${PACKAGES_DIR}/overlays/${ENV}/manifests/"*/; do
        [ -d "$dir" ] || continue
        copy_manifest_dir "$dir" "${DIST_DIR}/${ENV}"
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Generate Tailscale serve ConfigMaps from per-overlay JSON configs
# This replaces the templated ConfigMaps with concrete ones (no placeholders)
# ═══════════════════════════════════════════════════════════════════════════════
echo "Step 3: Generating Tailscale serve ConfigMaps..."

CONFIG_DIR="${PACKAGES_DIR}/overlays/${ENV}/configs"
if [ -d "$CONFIG_DIR" ]; then
    for json_file in "${CONFIG_DIR}"/*-serve.json; do
        [ -f "$json_file" ] || continue
        service=$(basename "$json_file" -serve.json)
        manifest_dir="${DIST_DIR}/${ENV}/${service}-tailscale-serve/manifests"

        if [ -d "$manifest_dir" ]; then
            # Read JSON content and escape for YAML single-quoted string
            json_content=$(cat "$json_file" | tr -d '\n' | sed "s/'/\\\\'/g")

            # Generate ConfigMap YAML
            cat > "${manifest_dir}/ConfigMap-${service}-tailscale-serve-config.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${service}-tailscale-serve-config
  namespace: tailscale
data:
  serve.json: '${json_content}'
EOF
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Substitute remaining host-specific values in YAML files
# This handles Deployment names, PVC names, TS_HOSTNAME env vars, etc.
# Note: ConfigMaps no longer need substitution (generated from JSON configs)
# ═══════════════════════════════════════════════════════════════════════════════
echo "Step 4: Substituting remaining host-specific values..."
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

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Remove orphaned manifest directories
# idpbuilder expects each top-level manifest directory to have a matching
# Application file (<name>.yaml). Keep only directories that have an app.
# ═══════════════════════════════════════════════════════════════════════════════
for dir in "${DIST_DIR}/${ENV}"/*/; do
    [ -d "$dir" ] || continue
    app=$(basename "$dir")
    if [ ! -f "${DIST_DIR}/${ENV}/${app}.yaml" ]; then
        rm -rf "$dir"
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Report results
# ═══════════════════════════════════════════════════════════════════════════════
app_count=$(ls -1 "${DIST_DIR}/${ENV}"/*.yaml 2>/dev/null | wc -l)
manifest_dirs=$(find "${DIST_DIR}/${ENV}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

echo ""
echo "Built ${ENV} environment:"
echo "  - ${app_count} ArgoCD Applications"
echo "  - ${manifest_dirs} manifest directories"
echo "  - Output: ${DIST_DIR}/${ENV}/"
