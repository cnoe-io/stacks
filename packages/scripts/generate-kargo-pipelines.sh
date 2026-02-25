#!/usr/bin/env bash
# Generate Kargo inner-loop pipelines from images.yaml configuration
#
# This script reads packages/base/manifests/kargo-inner-loop/images.yaml
# and generates Warehouse + Stage resources for each independently promoted image.
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

append_promoted_images() {
    local primary_image_name="$1"
    local warehouse_file="$2"
    local stage_file="$3"

    local dependent_rows
    dependent_rows=$(yq -r ".images[] | select((.promoteWith // \"\") == \"$primary_image_name\") | [(.name), (.imageName // .name), (.registry), (.org), (.tagStrategy), (.tagPattern), (.discoveryLimit // 10)] | @tsv" "$CONFIG_FILE")

    if [ -z "$dependent_rows" ]; then
        return 0
    fi

    echo "    Coupled promotions:"
    while IFS=$'\t' read -r dep_name dep_repo dep_registry dep_org dep_tag_strategy dep_tag_pattern dep_discovery_limit; do
        [ -n "${dep_name:-}" ] || continue

        local dep_repo_url="${dep_registry}/${dep_org}/${dep_repo}"
        local dep_var_name="imageRepoURL_${dep_name//-/_}"
        local dep_image_expr="\${{ vars.${dep_var_name} }}"
        local dep_tag_expr="\${{ imageFrom(vars.${dep_var_name}).Tag }}"

        echo "      - ${dep_name} (${dep_repo_url})"

        DEP_REPO_URL="$dep_repo_url" \
        DEP_TAG_STRATEGY="$dep_tag_strategy" \
        DEP_TAG_PATTERN="$dep_tag_pattern" \
        DEP_DISCOVERY_LIMIT="$dep_discovery_limit" \
        yq -iy '.spec.subscriptions += [{"image": {"repoURL": env.DEP_REPO_URL, "imageSelectionStrategy": env.DEP_TAG_STRATEGY, "allowTagsRegexes": [env.DEP_TAG_PATTERN], "discoveryLimit": (env.DEP_DISCOVERY_LIMIT | tonumber), "insecureSkipTLSVerify": true, "strictSemvers": false}}]' "$warehouse_file"

        sed -i "/^[[:space:]]*- name: imageRepoURL$/,/^[[:space:]]*value:/ {/^[[:space:]]*value:/a\\
        - name: ${dep_var_name}\\
          value: ${dep_repo_url}
        }" "$stage_file"

        sed -i "/tag: \${{ imageFrom(vars.imageRepoURL).Tag }}/a\\
              - image: ${dep_image_expr}\\
                tag: ${dep_tag_expr}
        " "$stage_file"
    done <<< "$dependent_rows"
}

for i in $(seq 0 $((image_count - 1))); do
    # Read image configuration (use -r for raw output without quotes)
    IMAGE_NAME=$(yq -r ".images[$i].name" "$CONFIG_FILE")
    IMAGE_REPO=$(yq -r ".images[$i].imageName // .images[$i].name" "$CONFIG_FILE")
    ARGOCD_APP=$(yq -r ".images[$i].argocdApp" "$CONFIG_FILE")
    REGISTRY=$(yq -r ".images[$i].registry" "$CONFIG_FILE")
    ORG=$(yq -r ".images[$i].org" "$CONFIG_FILE")
    TAG_STRATEGY=$(yq -r ".images[$i].tagStrategy" "$CONFIG_FILE")
    TAG_PATTERN=$(yq -r ".images[$i].tagPattern" "$CONFIG_FILE")
    DISCOVERY_LIMIT=$(yq -r ".images[$i].discoveryLimit // 10" "$CONFIG_FILE")
    PROMOTION_TYPE=$(yq -r ".images[$i].promotionType" "$CONFIG_FILE")
    PROMOTE_WITH=$(yq -r ".images[$i].promoteWith // \"\"" "$CONFIG_FILE")

    if [ -n "$PROMOTE_WITH" ]; then
        echo "  Skipping standalone generation: ${IMAGE_NAME} (promoted with ${PROMOTE_WITH})"
        continue
    fi

    echo "  Processing: $IMAGE_NAME ($PROMOTION_TYPE)"

    # Generate Warehouse
    WAREHOUSE_FILE="$OUTPUT_DIR/Warehouse-${IMAGE_NAME}.yaml"
    sed \
        -e "s|__IMAGE_NAME__|${IMAGE_NAME}|g" \
        -e "s|__IMAGE_REPO__|${IMAGE_REPO}|g" \
        -e "s|__ARGOCD_APP__|${ARGOCD_APP}|g" \
        -e "s|__REGISTRY__|${REGISTRY}|g" \
        -e "s|__ORG__|${ORG}|g" \
        -e "s|__TAG_STRATEGY__|${TAG_STRATEGY}|g" \
        -e "s|__TAG_PATTERN__|${TAG_PATTERN}|g" \
        -e "s|__DISCOVERY_LIMIT__|${DISCOVERY_LIMIT}|g" \
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
            -e "s|__IMAGE_REPO__|${IMAGE_REPO}|g" \
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
            -e "s|__IMAGE_REPO__|${IMAGE_REPO}|g" \
            -e "s|__ARGOCD_APP__|${ARGOCD_APP}|g" \
            -e "s|__REGISTRY__|${REGISTRY}|g" \
            -e "s|__ORG__|${ORG}|g" \
            "$TEMPLATE_FILE" > "$STAGE_FILE"

        # Add additional image subscriptions/promotion updates for images that
        # share this Stage via promoteWith.
        append_promoted_images "$IMAGE_NAME" "$WAREHOUSE_FILE" "$STAGE_FILE"

        # Check for optional verification configuration
        VERIFICATION_ENABLED=$(yq -r ".images[$i].verification.enabled // false" "$CONFIG_FILE")
        if [ "$VERIFICATION_ENABLED" = "true" ]; then
            ANALYSIS_TEMPLATE=$(yq -r ".images[$i].verification.analysisTemplate" "$CONFIG_FILE")
            # Append verification block to the Stage file
            cat >> "$STAGE_FILE" << EOF

  verification:
    analysisTemplates:
      - name: ${ANALYSIS_TEMPLATE}
    analysisRunMetadata:
      labels:
        app: ${IMAGE_NAME}
        kargo.akuity.io/loop: inner
EOF
        fi

        # NOTE: No separate Application file generated.
        # The base ArgoCD app (from active-development component) is the sole deployer.
        # Kargo Stage updates the main branch, and the base app syncs from main.
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
