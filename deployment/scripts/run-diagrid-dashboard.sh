#!/bin/bash
# Run Diagrid Dashboard locally with port-forwarded Redis
#
# The Diagrid Dashboard is designed for local Dapr CLI development and expects
# Redis keys without the Kubernetes app-id prefix. This script provides a
# workaround by port-forwarding Redis and running the dashboard locally.
#
# Note: Due to key format differences in Kubernetes, the dashboard may not
# show all workflow data. For full Kubernetes workflow visibility, consider
# using Diagrid Catalyst or the Dapr Dashboard.

set -e

REDIS_LOCAL_PORT="${REDIS_LOCAL_PORT:-6379}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"
NAMESPACE="${NAMESPACE:-dapr-agents}"
REDIS_SERVICE="${REDIS_SERVICE:-redis-service}"

echo "Starting Diagrid Dashboard for Dapr Workflow visualization..."
echo ""
echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Redis Service: $REDIS_SERVICE"
echo "  Local Redis Port: $REDIS_LOCAL_PORT"
echo "  Dashboard Port: $DASHBOARD_PORT"
echo ""

# Check if Redis port-forward is needed
if ! nc -z localhost $REDIS_LOCAL_PORT 2>/dev/null; then
    echo "Starting Redis port-forward..."
    kubectl port-forward -n "$NAMESPACE" "svc/$REDIS_SERVICE" "$REDIS_LOCAL_PORT:6379" &
    REDIS_PF_PID=$!
    sleep 2
    echo "Redis port-forward started (PID: $REDIS_PF_PID)"
else
    echo "Redis already accessible on localhost:$REDIS_LOCAL_PORT"
    REDIS_PF_PID=""
fi

# Create temporary state component file for host.docker.internal
TEMP_COMPONENT=$(mktemp /tmp/state_redis_XXXXXX.yaml)
cat > "$TEMP_COMPONENT" << EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: "host.docker.internal:$REDIS_LOCAL_PORT"
    - name: redisPassword
      value: ""
    - name: actorStateStore
      value: "true"
EOF

echo ""
echo "Starting Diagrid Dashboard container..."
echo "Access the dashboard at: http://localhost:$DASHBOARD_PORT"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Run the dashboard
docker run --rm -it \
    -p "$DASHBOARD_PORT:8080" \
    -v "$TEMP_COMPONENT:/app/components/custom_state.yaml" \
    -e COMPONENT_FILE=/app/components/custom_state.yaml \
    ghcr.io/diagridio/diagrid-dashboard:latest

# Cleanup
rm -f "$TEMP_COMPONENT"
if [ -n "$REDIS_PF_PID" ]; then
    kill $REDIS_PF_PID 2>/dev/null || true
fi
