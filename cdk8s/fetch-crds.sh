#!/usr/bin/env bash
set -euo pipefail

# fetch-crds.sh - Update vendored CRD files from upstream sources
#
# This script updates the CRD files in crds/ directory from their
# canonical upstream sources. Run this when you need to update to
# newer CRD versions.
#
# Usage:
#   ./fetch-crds.sh
#
# After running, commit the updated crds/ files:
#   git add crds/
#   git commit -m "chore: update CRDs to vX.Y.Z"

CRDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/crds" && pwd)"

echo "📦 Updating CRD files in ${CRDS_DIR}..."

# External Secrets Operator CRDs
echo "  → External Secrets Operator (main branch)..."
curl -sL https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml \
  -o "${CRDS_DIR}/external-secrets-crds.yaml"

# KGateway CRDs (solo.io Gateway Extension)
# Note: KGateway was removed - create placeholder
echo "  → KGateway (placeholder)..."
cat > "${CRDS_DIR}/kgateway-placeholder.yaml" <<'EOF'
# KGateway was removed - placeholder CRD file for cdk8s import
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: placeholder.example.com
spec:
  group: example.com
  names:
    kind: Placeholder
    listKind: PlaceholderList
    plural: placeholders
    singular: placeholder
  scope: Namespaced
  versions:
  - name: v1
    schema:
      openAPIV3Schema:
        type: object
    served: true
    storage: true
EOF

# Tailscale ProxyGroup CRD
echo "  → Tailscale ProxyGroups (main branch)..."
curl -sL https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_proxygroups.yaml \
  -o "${CRDS_DIR}/tailscale-proxygroups-crd.yaml"

# kmcp MCPServer CRD
echo "  → kmcp MCPServer (main branch)..."
curl -sL https://raw.githubusercontent.com/kagent-dev/kmcp/main/config/crd/bases/kagent.dev_mcpservers.yaml \
  -o "${CRDS_DIR}/kmcp-mcpserver-crd.yaml"

echo ""
echo "✅ CRD files updated in ${CRDS_DIR}"
echo ""
echo "📝 Next steps:"
echo "   1. Run 'npm run import' to regenerate TypeScript types"
echo "   2. Commit the updated CRDs: git add crds/ && git commit -m 'chore: update CRDs'"
echo ""
echo "⚠️  NOTE: kagent CRDs are NOT fetched by this script."
echo "   The ai-platform-engineering Helm chart does not publish CRDs."
echo "   The imports/kagent.dev.ts file is committed to the repo and must be preserved."
