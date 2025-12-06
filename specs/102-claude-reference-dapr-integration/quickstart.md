# Quickstart: Claude SDK + Dapr Multi-Agent Integration

**Feature**: 102-claude-reference-dapr-integration
**Date**: 2025-12-06

## Prerequisites

- Kubernetes cluster with Dapr runtime installed (sidecar injection enabled)
- ArgoCD configured for GitOps deployments
- External Secrets Operator with Azure Key Vault ClusterSecretStore
- Redis available in cluster
- Langfuse v2.50+ deployed and accessible
- Jaeger with Zipkin-compatible collector endpoint

---

## Step 1: Deploy Infrastructure Components

### 1.1 Verify Dapr Installation

```bash
# Check Dapr system pods
kubectl get pods -n dapr-system
# Expected: dapr-operator, dapr-sidecar-injector, dapr-placement, dapr-sentry

# Verify Dapr version
dapr version
# Expected: 1.12+ recommended
```

### 1.2 Deploy Redis (if not already present)

```bash
# Using Helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install redis bitnami/redis -n speckit --create-namespace \
  --set auth.enabled=false \
  --set replica.replicaCount=0
```

### 1.3 Deploy Dapr Components

Synthesize and deploy via cdk8s:

```bash
cd cdk8s
npx ts-node main-v2.ts

# Deploy Dapr components package
idpbuilder create --package dist/speckit-dapr-components
```

Verify components:

```bash
kubectl get components -n speckit
# Expected: messagepubsub, workflowstatestore, agentregistrystore, memorystore
```

---

## Step 2: Configure Observability

### 2.1 Langfuse Setup

Ensure Langfuse is deployed with accessible endpoint:

```bash
kubectl get pods -n langfuse
kubectl get svc -n langfuse
```

Get Langfuse credentials:

```bash
# Public key and secret key should be in Azure Key Vault
# Verify External Secret sync:
kubectl get externalsecret -n speckit langfuse-credentials
```

### 2.2 Jaeger Setup

Verify Jaeger collector endpoint:

```bash
kubectl get svc -n jaeger
# Note the Zipkin collector endpoint (typically port 9411)
```

### 2.3 Deploy Tracing Configuration

```yaml
# Apply Dapr tracing config
kubectl apply -f - <<EOF
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: dapr-tracing-config
  namespace: speckit
spec:
  tracing:
    samplingRate: "1"
    zipkin:
      endpointAddress: "http://jaeger-collector.jaeger.svc.cluster.local:9411/api/v2/spans"
EOF
```

---

## Step 3: Configure Secrets

### 3.1 Create External Secrets

Deploy secrets via cdk8s:

```bash
# Ensure speckit-agents-secrets package includes:
# - ANTHROPIC-API-KEY
# - LANGFUSE-PUBLIC-KEY
# - LANGFUSE-SECRET-KEY
# - WORKFLOW-API-KEY

idpbuilder create --package dist/speckit-agents-secrets
```

Verify secrets synced:

```bash
kubectl get secrets -n speckit
# Expected: anthropic-api-key, langfuse-credentials, workflow-api-key
```

---

## Step 4: Deploy Agent Services

### 4.1 Build Agent Container Images

```bash
# Build and push images (if using local registry)
docker build -t gitea.cnoe.localtest.me:8443/giteaadmin/speckit-agents:latest ./src/agents/
docker push gitea.cnoe.localtest.me:8443/giteaadmin/speckit-agents:latest
```

### 4.2 Deploy via ArgoCD

```bash
# Synthesize agent deployments
cd cdk8s
npx ts-node main-v2.ts

# Deploy agents package
idpbuilder create --package dist/speckit-agents
```

### 4.3 Verify Agent Pods

```bash
kubectl get pods -n speckit -l app.kubernetes.io/part-of=speckit-agents
# Expected pods:
# - orchestrator-xxx (Running)
# - specifier-xxx (Running)
# - planner-xxx (Running)
# - taskgenerator-xxx (Running)
# - implementer-xxx (Running)

# Check Dapr sidecar injection
kubectl get pods -n speckit -o jsonpath='{.items[*].spec.containers[*].name}' | tr ' ' '\n' | grep daprd
# Should show daprd for each agent pod
```

---

## Step 5: Verify Agent Registration

### 5.1 Check Agent Registry

```bash
# Port-forward to Redis
kubectl port-forward -n speckit svc/redis-master 6379:6379 &

# Query registry
redis-cli GET "registry:speckit" | jq .
```

Expected output:

```json
{
  "team_name": "speckit",
  "agents": {
    "orchestrator": {"status": "active", ...},
    "specifier": {"status": "active", ...},
    "planner": {"status": "active", ...},
    "taskgenerator": {"status": "active", ...},
    "implementer": {"status": "active", ...}
  }
}
```

### 5.2 Check Agent Logs

```bash
# Orchestrator logs
kubectl logs -n speckit -l app=orchestrator --tail=50

# Specifier logs
kubectl logs -n speckit -l app=specifier --tail=50
```

---

## Step 6: Submit Test Workflow

### 6.1 Get API Endpoint

```bash
# Via ingress
curl -k https://speckit-api.cnoe.localtest.me:8443/health

# Or port-forward
kubectl port-forward -n speckit svc/workflow-api 8080:8080 &
curl http://localhost:8080/health
```

### 6.2 Submit Workflow

```bash
# Get API key from secret
API_KEY=$(kubectl get secret -n speckit workflow-api-key -o jsonpath='{.data.api-key}' | base64 -d)

# Submit workflow
curl -X POST http://localhost:8080/run \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "description": "Add a hello world REST endpoint that returns a greeting message with the current timestamp"
  }'
```

Expected response:

```json
{
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "status_url": "/workflows/550e8400-e29b-41d4-a716-446655440000/status",
  "created_at": "2025-12-06T10:30:00Z"
}
```

### 6.3 Monitor Workflow Progress

```bash
# Query status
curl http://localhost:8080/workflows/550e8400-e29b-41d4-a716-446655440000/status \
  -H "X-API-Key: $API_KEY" | jq .

# Watch logs
kubectl logs -n speckit -l app=orchestrator -f
```

---

## Step 7: Verify Observability

### 7.1 Check Langfuse Traces

1. Open Langfuse dashboard (e.g., `https://langfuse.cnoe.localtest.me:8443`)
2. Navigate to Traces
3. Filter by session ID (workflow_id)
4. Verify:
   - All agent generations appear
   - Tool calls are recorded with inputs/outputs
   - Token usage is captured

### 7.2 Check Jaeger Traces

1. Open Jaeger UI (e.g., `https://jaeger.cnoe.localtest.me:8443`)
2. Search by tag: `workflow.id=550e8400-...`
3. Verify:
   - Distributed trace shows complete flow
   - Spans for each agent: Orchestrator → Specifier → Planner → TaskGenerator → Implementer
   - Phase transitions are visible

### 7.3 Correlation Check

1. In Langfuse, find a trace and note the trace ID
2. In Jaeger, search for the same workflow ID
3. Verify timestamps align (within 1 second tolerance)
4. Check that Langfuse metadata contains Jaeger trace ID

---

## Step 8: End-to-End Test Scenarios

### 8.1 Simple Workflow (Happy Path)

```bash
# Submit simple feature
curl -X POST http://localhost:8080/run \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"description": "Add a health check endpoint that returns service status"}'

# Wait for completion (simple workflow ~10 minutes)
# Poll status until completed
```

### 8.2 Timeout Test

```bash
# Submit complex feature that may timeout
curl -X POST http://localhost:8080/run \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"description": "Implement a complete user management system with registration, authentication, password reset, and role-based access control"}'

# Monitor for retry behavior
kubectl logs -n speckit -l app=orchestrator -f | grep -i "retry\|timeout"
```

### 8.3 Concurrent Workflow Test

```bash
# Submit 6 workflows (exceeds limit of 5)
for i in {1..6}; do
  curl -X POST http://localhost:8080/run \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d "{\"description\": \"Test workflow $i: Add feature $i\"}" &
done
wait

# Check for queued workflows
curl http://localhost:8080/workflows \
  -H "X-API-Key: $API_KEY" | jq '.[] | select(.status == "queued")'
```

---

## Troubleshooting

### Agent Not Registering

```bash
# Check Dapr sidecar is running
kubectl get pods -n speckit -l app=specifier -o yaml | grep -A5 "name: daprd"

# Check component connectivity
kubectl exec -n speckit deploy/specifier -c daprd -- wget -qO- http://localhost:3500/v1.0/healthz
```

### Langfuse Traces Not Appearing

```bash
# Check Langfuse connectivity from agent
kubectl exec -n speckit deploy/specifier -- curl -s https://cloud.langfuse.com/health

# Verify credentials
kubectl get secret -n speckit langfuse-credentials -o yaml

# Check agent logs for Langfuse errors
kubectl logs -n speckit -l app=specifier | grep -i langfuse
```

### Jaeger Traces Missing

```bash
# Verify Dapr tracing config
kubectl get configuration -n speckit dapr-tracing-config -o yaml

# Check Zipkin endpoint reachable
kubectl exec -n speckit deploy/specifier -c daprd -- wget -qO- http://jaeger-collector.jaeger:9411/health
```

### Workflow Stuck in Phase

```bash
# Check agent logs
kubectl logs -n speckit -l app=planner --tail=100

# Query workflow state
redis-cli GET "workflow:$WORKFLOW_ID" | jq .

# Check for timeout
kubectl logs -n speckit -l app=orchestrator | grep "$WORKFLOW_ID"
```

---

## Success Criteria Verification

| Criteria | Verification Command | Expected Result |
|----------|---------------------|-----------------|
| SC-001: LLM generations in Langfuse | Langfuse UI → Session filter | All generations visible within 30s |
| SC-002: Tool invocations recorded | Langfuse UI → Spans tab | Tool calls with I/O visible |
| SC-003: Jaeger distributed traces | Jaeger UI → Service filter | Complete workflow path |
| SC-004: Workflow ID session grouping | Langfuse UI → Session ID search | All agents grouped |
| SC-005: Workflow ID Jaeger search | Jaeger UI → Tag search | Single trace shows all agents |
| SC-006: Simple workflow completion | Status endpoint | Completed in <50 minutes |
| SC-007: Agent startup time | Pod logs | Registered in <60 seconds |
| SC-008: Graceful degradation | Disable Langfuse, run workflow | Workflow completes with warning |
| SC-009: Token usage accuracy | Compare Langfuse vs API billing | Within 5% |
| SC-010: Cross-system correlation | Langfuse metadata + Jaeger tags | IDs match |

---

## Step 9: Verify Prometheus Metrics

### 9.1 Check Metrics Endpoint

```bash
# Port-forward to an agent
kubectl port-forward -n speckit deploy/orchestrator 8000:8000 &

# Query metrics
curl http://localhost:8000/metrics

# Expected metrics:
# - speckit_workflow_total{status="...",agent="..."}
# - speckit_workflow_duration_seconds_bucket{...}
# - speckit_phase_total{phase="...",status="...",agent="..."}
# - speckit_llm_requests_total{model="...",agent="...",status="..."}
# - speckit_llm_tokens_total{model="...",agent="...",direction="..."}
# - speckit_tool_invocations_total{tool="...",agent="...",status="..."}
```

### 9.2 Prometheus Integration (Optional)

```yaml
# Apply ServiceMonitor for Prometheus scraping
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: speckit-agents
  namespace: speckit
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: speckit-agents
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF
```

---

## Step 10: Test Session Recovery

### 10.1 Simulate Pod Restart

```bash
# Get workflow in progress
WORKFLOW_ID=$(curl -s http://localhost:8080/workflows -H "X-API-Key: $API_KEY" | jq -r '.[0].id')

# Delete the agent pod to simulate failure
kubectl delete pod -n speckit -l app=planner --force

# Wait for new pod
kubectl wait --for=condition=ready pod -n speckit -l app=planner --timeout=120s

# Check workflow recovery
curl "http://localhost:8080/workflows/$WORKFLOW_ID/status" -H "X-API-Key: $API_KEY" | jq .

# Expected: Workflow should resume from last checkpoint
```

### 10.2 Query Checkpoints

```bash
# Check checkpoint data via Redis
redis-cli KEYS "checkpoint:*" | head -5
redis-cli GET "checkpoint:$WORKFLOW_ID" | jq .

# Expected fields:
# - session_id
# - phase
# - step_index
# - total_steps
# - conversation_history (for Claude SDK resumption)
```

---

## Development Commands

### Local Development Setup

```bash
cd speckit-agents

# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -e ".[dev]"

# Copy environment template
cp .env.example .env
# Edit .env with your values

# Run tests
pytest tests/ -v

# Run specific test categories
pytest tests/unit/ -v           # Unit tests
pytest tests/contract/ -v       # Contract tests
pytest tests/integration/ -v    # Integration tests (requires Dapr)
```

### Run Single Agent Locally

```bash
# Set environment variables
export AGENT_NAME=specifier
export DAPR_HTTP_PORT=3500
export LANGFUSE_ENABLED=true
# ... other variables from .env

# Run with Dapr sidecar
dapr run --app-id specifier --app-port 8000 -- python -m uvicorn src.main:app --host 0.0.0.0 --port 8000
```

### Docker Build

```bash
cd speckit-agents

# Build image
docker build -t speckit-agents:local .

# Run with docker-compose (for local testing)
docker-compose up -d
```

---

## API Reference

### Health Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/healthz` | GET | Liveness probe |
| `/ready` | GET | Readiness probe (Dapr connectivity) |
| `/status` | GET | Detailed component status |
| `/metrics` | GET | Prometheus metrics |

### Workflow API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/run` | POST | Submit new workflow |
| `/workflows` | GET | List all workflows |
| `/workflows/{id}/status` | GET | Get workflow status |
| `/workflows/{id}` | DELETE | Cancel workflow |

### Authentication

All workflow endpoints require `X-API-Key` header:

```bash
curl -H "X-API-Key: your-api-key" http://localhost:8080/run
```

Rate limits:
- Default: 100 requests/minute
- Service keys: 1000 requests/minute

---

## Cleanup

```bash
# Remove test workflows
redis-cli KEYS "workflow:*" | xargs redis-cli DEL

# Remove test artifacts
redis-cli KEYS "artifact:*" | xargs redis-cli DEL

# Remove sessions and checkpoints
redis-cli KEYS "session:*" | xargs redis-cli DEL
redis-cli KEYS "checkpoint:*" | xargs redis-cli DEL

# Reset agent registry (force re-registration)
redis-cli DEL "registry:speckit"
kubectl rollout restart deployment -n speckit -l app.kubernetes.io/part-of=speckit-agents
```
