#!/usr/bin/env bash
# Build and push shared devcontainer images to Gitea registry
#
# This script ALWAYS builds images before pushing.
# For smart push (existing images only), use: deployment/scripts/push-devcontainers.sh
#
# Usage:
#   ./build-push.sh              # Build and push all
#   ./build-push.sh nodejs       # Build and push Node.js only
#   ./build-push.sh python       # Build and push Python only
#   ./build-push.sh hybrid       # Build and push Node.js+Python hybrid
#   ./build-push.sh all          # Build and push all images
#
# When to use this script vs push-devcontainers.sh:
#   - build-push.sh: First time setup, Dockerfile changes, or manual rebuilds
#   - push-devcontainers.sh: cluster-recreate (pushes existing images quickly)

set -euo pipefail

REGISTRY="${REGISTRY:-gitea.cnoe.localtest.me}"
ORG="${ORG:-giteaadmin}"

cd "$(dirname "$0")"

build_nodejs() {
    echo ">>> Building nodejs-22-devspace..."
    docker build \
        -t "${REGISTRY}/${ORG}/nodejs-22-devspace:latest" \
        -f Dockerfile.nodejs-22 \
        .

    echo ">>> Pushing nodejs-22-devspace..."
    docker push "${REGISTRY}/${ORG}/nodejs-22-devspace:latest"

    echo ">>> nodejs-22-devspace pushed successfully!"
}

build_python() {
    echo ">>> Building python-312-devspace..."
    docker build \
        -t "${REGISTRY}/${ORG}/python-312-devspace:latest" \
        -f Dockerfile.python-312 \
        .

    echo ">>> Pushing python-312-devspace..."
    docker push "${REGISTRY}/${ORG}/python-312-devspace:latest"

    echo ">>> python-312-devspace pushed successfully!"
}

build_hybrid() {
    echo ">>> Building nodejs-python-devspace (hybrid)..."
    docker build \
        -t "${REGISTRY}/${ORG}/nodejs-python-devspace:latest" \
        -f Dockerfile.nodejs-python \
        .

    echo ">>> Pushing nodejs-python-devspace..."
    docker push "${REGISTRY}/${ORG}/nodejs-python-devspace:latest"

    echo ">>> nodejs-python-devspace pushed successfully!"
}

case "${1:-all}" in
    nodejs|node)
        build_nodejs
        ;;
    python|py)
        build_python
        ;;
    hybrid|both)
        build_hybrid
        ;;
    all)
        build_nodejs
        build_python
        build_hybrid
        ;;
    *)
        echo "Usage: $0 [nodejs|python|hybrid|all]"
        echo ""
        echo "Images:"
        echo "  nodejs  - Node.js 22 only (for pure Node.js/Next.js apps)"
        echo "  python  - Python 3.12 only (for pure Python/FastAPI apps)"
        echo "  hybrid  - Node.js 22 + Python 3.12 (for agent apps needing both)"
        echo "  all     - Build all images"
        exit 1
        ;;
esac

echo ""
echo "=== Available shared devcontainer images ==="
echo "  ${REGISTRY}/${ORG}/nodejs-22-devspace:latest       (Node.js only)"
echo "  ${REGISTRY}/${ORG}/python-312-devspace:latest      (Python only)"
echo "  ${REGISTRY}/${ORG}/nodejs-python-devspace:latest   (Node.js + Python)"
