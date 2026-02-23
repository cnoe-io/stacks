#!/usr/bin/env bash
# Generate per-overlay serve.json config files for Tailscale serve proxies
# These configs are used by configMapGenerator in each overlay's kustomization.yaml
#
# Usage: ./generate-serve-configs.sh [overlay]
#   If overlay is specified, only generate for that overlay
#   If not specified, generate for all overlays

set -e

PACKAGES_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Service definitions: name -> proxy_target
declare -A SERVICES=(
    ["ai-chatbot"]="http://ai-chatbot.ai-chatbot.svc.cluster.local:3000"
    ["argo-workflows"]="http://argo-workflows-server.argo.svc.cluster.local:2746"
    ["argocd"]="https://argocd-server.argocd.svc.cluster.local:443"
    ["backstage"]="http://backstage.backstage.svc.cluster.local:7007"
    ["caipe"]="http://caipe-supervisor.caipe.svc.cluster.local:80"
    ["crawl4ai"]="http://crawl4ai.ai-platform-engineering.svc.cluster.local:11235"
    ["dapr"]="http://dapr-dashboard.dapr-system.svc.cluster.local:8080"
    ["flipt"]="http://flipt.feature-flags.svc.cluster.local:8080"
    ["gitea"]="http://my-gitea-http.gitea.svc.cluster.local:3000"
    ["grafana"]="http://kube-prometheus-stack-grafana.observability.svc.cluster.local:80"
    ["kagent"]="http://kagent-dashboard.kagent.svc.cluster.local:3000"
    ["kargo"]="http://kargo-api.kargo.svc.cluster.local:80"
    ["keycloak"]="https://keycloak.keycloak.svc.cluster.local:443"
    ["langfuse"]="http://langfuse-web.langfuse.svc.cluster.local:3000"
    ["loki"]="http://loki.observability.svc.cluster.local:3100"
    ["mcp-inspector-client"]="http://mcp-inspector-client.workflow-builder.svc.cluster.local:6274"
    ["mcp-inspector-proxy"]="http://mcp-inspector-proxy.workflow-builder.svc.cluster.local:6277"
    ["mimir"]="http://mimir.observability.svc.cluster.local:9009"
    ["nocodb"]="http://nocodb.nocodb.svc.cluster.local:8080"
    ["otel-collector"]="http://otel-collector.observability.svc.cluster.local:4318"
    ["phoenix"]="http://arize-phoenix.observability.svc.cluster.local:6006"
    ["redisinsight"]="http://redisinsight.observability.svc.cluster.local:5540"
)

# Overlay -> TAILSCALE_HOST mapping
declare -A HOSTS=(
    ["kind"]="localdev"
    ["kind-ryzen"]="ryzen"
    ["kind-thinkpad"]="thinkpad"
    ["talos"]="talos"
    ["hub"]="hub"
)

TAILNET="tail286401.ts.net"

generate_overlay() {
    local overlay="$1"
    local host="${HOSTS[$overlay]}"

    if [[ -z "$host" ]]; then
        echo "Unknown overlay: $overlay"
        return 1
    fi

    local config_dir="${PACKAGES_DIR}/overlays/${overlay}/configs"
    mkdir -p "$config_dir"

    echo "Generating configs for $overlay (host=$host)..."

    for service in "${!SERVICES[@]}"; do
        local proxy="${SERVICES[$service]}"
        local hostname="${service}-${host}.${TAILNET}"
        local output_file="${config_dir}/${service}-serve.json"

        # Generate pretty-printed JSON
        cat > "$output_file" << EOF
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "${hostname}:443": {
      "Handlers": {
        "/": {
          "Proxy": "${proxy}"
        }
      }
    }
  }
}
EOF
        echo "  - ${service}-serve.json"
    done
}

# Main
if [[ -n "$1" ]]; then
    # Generate for specific overlay
    generate_overlay "$1"
else
    # Generate for all overlays
    for overlay in "${!HOSTS[@]}"; do
        generate_overlay "$overlay"
    done
fi

echo ""
echo "Done. Generated serve.json files in overlays/*/configs/"
