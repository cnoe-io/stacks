#!/bin/bash
# Port forward all major services for Codespaces access
# This script starts port forwards in the background for easy access to all services

set -e

PIDS_FILE="/tmp/port-forwards.pids"
LOGS_DIR="/tmp/port-forward-logs"

# Create logs directory
mkdir -p "$LOGS_DIR"

# Clean up existing port forwards
if [ -f "$PIDS_FILE" ]; then
    echo "🧹 Cleaning up existing port forwards..."
    while read -r pid; do
        kill "$pid" 2>/dev/null || true
    done < "$PIDS_FILE"
    rm "$PIDS_FILE"
fi

# Function to start a port forward
start_port_forward() {
    local service=$1
    local namespace=$2
    local local_port=$3
    local remote_port=$4
    local label=$5

    echo "🔌 Starting port forward: $label ($local_port -> $service:$remote_port)"
    kubectl port-forward -n "$namespace" "svc/$service" "$local_port:$remote_port" \
        > "$LOGS_DIR/$service.log" 2>&1 &
    echo $! >> "$PIDS_FILE"
    sleep 1
}

echo "🚀 Starting port forwards for all services..."
echo ""

# ArgoCD (8080 -> 443)
start_port_forward "argocd-server" "argocd" 8080 443 "ArgoCD"

# Backstage (7007 -> 7007)
start_port_forward "backstage" "backstage" 7007 7007 "Backstage"

# Gitea (3000 -> 3000)
start_port_forward "my-gitea-http" "gitea" 3000 3000 "Gitea"

# Keycloak (8081 -> 8080)
start_port_forward "keycloak" "keycloak" 8081 8080 "Keycloak"

# Kargo (8082 -> 80)
start_port_forward "kargo-api" "kargo" 8082 80 "Kargo"

# Headlamp (8083 -> 80)
start_port_forward "headlamp" "headlamp" 8083 80 "Headlamp"

# Argo Workflows (8085 -> 2746)
if kubectl get namespace argo &>/dev/null; then
    start_port_forward "argo-server" "argo" 8085 2746 "Argo Workflows"
fi

# Kagent Dashboard (8084 -> 8082) - only if kagent namespace exists
if kubectl get namespace kagent &>/dev/null; then
    start_port_forward "kagent-dashboard" "kagent" 8084 8082 "Kagent Dashboard"
fi

echo ""
echo "✅ All port forwards started!"
echo ""
echo "📋 Access services via the PORTS tab in VS Code:"
echo "   - ArgoCD:         port 8080 (https)"
echo "   - Backstage:      port 7007 (http)"
echo "   - Gitea:          port 3000 (http)"
echo "   - Keycloak:       port 8081 (http)"
echo "   - Kargo:          port 8082 (http)"
echo "   - Headlamp:       port 8083 (http)"
echo "   - Argo Workflows: port 8085 (http)"
if kubectl get namespace kagent &>/dev/null; then
    echo "   - Kagent:         port 8084 (http)"
fi
echo ""
echo "🔍 To view logs: ls -la $LOGS_DIR"
echo "🛑 To stop all:  kill \$(cat $PIDS_FILE)"
echo ""
echo "PIDs saved to: $PIDS_FILE"
