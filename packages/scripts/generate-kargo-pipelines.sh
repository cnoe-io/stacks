#!/usr/bin/env bash
# Generate Kargo inner-loop pipelines from images.yaml configuration
#
# This script reads packages/base/manifests/kargo-inner-loop/images.yaml
# and generates Warehouse + Stage resources for each image.
#
# Usage: ./generate-kargo-pipelines.sh
#
# The generated manifests use ${TAILSCALE_HOST} placeholder which is
# substituted by build.sh at build time for each target environment.
#
# Prerequisites:
#   - yq (mikefarah/yq) for YAML parsing
#
# Output:
#   packages/base/manifests/kargo-inner-loop/manifests/*.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_DIR="$(dirname "$SCRIPT_DIR")"
KARGO_DIR="${PACKAGES_DIR}/base/manifests/kargo-inner-loop"
CONFIG_FILE="${KARGO_DIR}/images.yaml"
TEMPLATES_DIR="${KARGO_DIR}/_templates"
OUTPUT_DIR="${KARGO_DIR}/manifests"

# Check prerequisites
if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (mikefarah/yq) is required but not found"
    echo "Install with: nix-shell -p yq-go"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "Generating Kargo inner-loop pipelines..."
echo "  Config: $CONFIG_FILE"
echo "  Output: $OUTPUT_DIR"

# Clean previous output
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Read images from config using yq
image_count=$(yq '.images | length' "$CONFIG_FILE")

if [ "$image_count" -eq 0 ]; then
    echo "WARNING: No images defined in $CONFIG_FILE"
    exit 0
fi

echo "  Found $image_count image(s) to process"
echo ""

for i in $(seq 0 $((image_count - 1))); do
    # Read image configuration (use -r for raw output without quotes)
    IMAGE_NAME=$(yq -r ".images[$i].name" "$CONFIG_FILE")
    ARGOCD_APP=$(yq -r ".images[$i].argocdApp" "$CONFIG_FILE")
    REGISTRY=$(yq -r ".images[$i].registry" "$CONFIG_FILE")
    ORG=$(yq -r ".images[$i].org" "$CONFIG_FILE")
    TAG_STRATEGY=$(yq -r ".images[$i].tagStrategy" "$CONFIG_FILE")
    TAG_PATTERN=$(yq -r ".images[$i].tagPattern" "$CONFIG_FILE")
    PROMOTION_TYPE=$(yq -r ".images[$i].promotionType" "$CONFIG_FILE")

    echo "  Processing: $IMAGE_NAME ($PROMOTION_TYPE)"

    # Generate Warehouse
    WAREHOUSE_FILE="$OUTPUT_DIR/Warehouse-${IMAGE_NAME}.yaml"
    sed \
        -e "s|__IMAGE_NAME__|${IMAGE_NAME}|g" \
        -e "s|__REGISTRY__|${REGISTRY}|g" \
        -e "s|__ORG__|${ORG}|g" \
        -e "s|__TAG_STRATEGY__|${TAG_STRATEGY}|g" \
        -e "s|__TAG_PATTERN__|${TAG_PATTERN}|g" \
        "$TEMPLATES_DIR/Warehouse.yaml.tpl" > "$WAREHOUSE_FILE"

    # Generate Stage (select template based on promotion type)
    STAGE_FILE="$OUTPUT_DIR/Stage-${IMAGE_NAME}-local-dev.yaml"
    if [ "$PROMOTION_TYPE" = "helm" ]; then
        TEMPLATE_FILE="$TEMPLATES_DIR/Stage-local-dev-helm.yaml.tpl"
        # Read helm-specific fields
        HELM_REPO_URL=$(yq -r ".images[$i].helmRepoURL" "$CONFIG_FILE")
        HELM_CHART=$(yq -r ".images[$i].helmChart" "$CONFIG_FILE")
        HELM_IMAGE_KEY=$(yq -r ".images[$i].helmImageKey" "$CONFIG_FILE")

        sed \
            -e "s|__IMAGE_NAME__|${IMAGE_NAME}|g" \
            -e "s|__ARGOCD_APP__|${ARGOCD_APP}|g" \
            -e "s|__REGISTRY__|${REGISTRY}|g" \
            -e "s|__ORG__|${ORG}|g" \
            -e "s|__HELM_REPO_URL__|${HELM_REPO_URL}|g" \
            -e "s|__HELM_CHART__|${HELM_CHART}|g" \
            -e "s|__HELM_IMAGE_KEY__|${HELM_IMAGE_KEY}|g" \
            "$TEMPLATE_FILE" > "$STAGE_FILE"
    else
        TEMPLATE_FILE="$TEMPLATES_DIR/Stage-local-dev-kustomize.yaml.tpl"
        # Kustomize template uses ${TAILSCALE_HOST} placeholder
        # which build.sh substitutes at build time
        sed \
            -e "s|__IMAGE_NAME__|${IMAGE_NAME}|g" \
            -e "s|__ARGOCD_APP__|${ARGOCD_APP}|g" \
            -e "s|__REGISTRY__|${REGISTRY}|g" \
            -e "s|__ORG__|${ORG}|g" \
            "$TEMPLATE_FILE" > "$STAGE_FILE"

        # Generate ArgoCD Application for local-dev (tracks stage/local-dev branch)
        APP_FILE="$OUTPUT_DIR/Application-${IMAGE_NAME}-local-dev.yaml"
        sed \
            -e "s|__IMAGE_NAME__|${IMAGE_NAME}|g" \
            -e "s|__ARGOCD_APP__|${ARGOCD_APP}|g" \
            "$TEMPLATES_DIR/Application-local-dev.yaml.tpl" > "$APP_FILE"
    fi
done

# Count generated files
warehouse_count=$(ls -1 "$OUTPUT_DIR"/Warehouse-*.yaml 2>/dev/null | wc -l)
stage_count=$(ls -1 "$OUTPUT_DIR"/Stage-*.yaml 2>/dev/null | wc -l)

echo ""
echo "Generated:"
echo "  - $warehouse_count Warehouse(s)"
echo "  - $stage_count Stage(s)"
echo "  - Output: $OUTPUT_DIR/"
echo ""
echo "Note: Manifests contain \${TAILSCALE_HOST} placeholder."
echo "      build.sh will substitute this for each target environment."
