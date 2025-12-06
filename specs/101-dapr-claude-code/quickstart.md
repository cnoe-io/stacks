# Quickstart: Claude Agent SDK + Dapr Integration

**Feature Branch**: `101-dapr-claude-code`
**Created**: 2025-12-05

## Prerequisites

- Python 3.11+
- Docker + Kind cluster
- `idpbuilder` CLI installed
- Anthropic API key (`ANTHROPIC_API_KEY`)

## Quick Deploy

### 1. Set up the Kind cluster with Dapr

```bash
# Create cluster with idpbuilder (includes ArgoCD, Gitea, ingress)
idpbuilder create --package cdk8s/dist/

# Verify Dapr is running
kubectl get pods -n dapr-system
# Expected: dapr-operator, dapr-sidecar-injector, dapr-placement, dapr-sentry
```

### 2. Configure API keys

Ensure External Secrets has synced the Anthropic API key from Azure Key Vault:

```bash
# Check secret exists
kubectl get secret dapr-agents-llm-providers -n dapr-agents -o yaml

# Verify ANTHROPIC_API_KEY is present
kubectl get secret dapr-agents-llm-providers -n dapr-agents \
  -o jsonpath='{.data.ANTHROPIC_API_KEY}' | base64 -d && echo
```

### 3. Deploy SpecKit Agents

```bash
# Synthesize CDK8s charts
cd cdk8s
npx ts-node main-v2.ts

# Deploy via ArgoCD (already handled by idpbuilder)
# Or apply directly for testing:
kubectl apply -f dist/speckit-agents/manifests/

# Wait for agents to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=speckit \
  -n dapr-agents --timeout=120s
```

### 4. Verify deployment

```bash
# Check all agent pods
kubectl get pods -n dapr-agents -l app.kubernetes.io/part-of=speckit
# Expected: 5 pods (orchestrator, specifier, planner, task-generator, implementer)

# Check Dapr sidecar injection
kubectl get pods -n dapr-agents -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
# Each pod should have: <agent-name> daprd

# Check health endpoints
kubectl port-forward -n dapr-agents svc/speckit-orchestrator 8000:8000 &
curl http://localhost:8000/healthz
# Expected: {"status":"ok"}
```

## Usage

### Start a workflow

```bash
# Port-forward orchestrator
kubectl port-forward -n dapr-agents svc/speckit-orchestrator 8000:8000 &

# Submit feature request
curl -X POST http://localhost:8000/run \
  -H "Content-Type: application/json" \
  -d '{"task": "Add user authentication with OAuth2 support"}'

# Response:
# {"instance_id":"550e8400-e29b-41d4-a716-446655440000","status":"specifying","status_url":"/status/550e8400-e29b-41d4-a716-446655440000"}
```

### Check workflow status

```bash
curl http://localhost:8000/status/550e8400-e29b-41d4-a716-446655440000

# Response:
# {
#   "id": "550e8400-e29b-41d4-a716-446655440000",
#   "status": "planning",
#   "current_phase": "planning",
#   "current_agent": "planner",
#   "progress_percent": 50,
#   "artifacts": [
#     {"type": "spec", "path": "550e8400-e29b-41d4-a716-446655440000/spec.md", ...}
#   ],
#   ...
# }
```

### View generated artifacts

```bash
# Access artifacts from agent pod
kubectl exec -n dapr-agents deploy/speckit-orchestrator -- \
  cat /artifacts/550e8400-e29b-41d4-a716-446655440000/spec.md
```

## Local Development

### Run agents locally (without Kubernetes)

```bash
cd speckit-agents

# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -e ".[dev]"

# Set environment variables
export ANTHROPIC_API_KEY="sk-ant-..."
export LANGFUSE_HOST="http://localhost:3000"
export LANGFUSE_PUBLIC_KEY="pk-..."
export LANGFUSE_SECRET_KEY="sk-..."

# Start Dapr sidecar (requires local Redis)
docker run -d --name redis -p 6379:6379 redis:7

# Run individual agent
AGENT_NAME=specifier dapr run --app-id speckit-specifier --app-port 8001 \
  --dapr-http-port 3500 --resources-path ./dapr-components \
  -- python -m src.main
```

### Run tests

```bash
cd speckit-agents
pytest tests/ -v --cov=src
```

## Observability

### View Langfuse traces

1. Port-forward Langfuse:
   ```bash
   kubectl port-forward -n observability svc/langfuse 3000:3000
   ```

2. Open http://localhost:3000

3. Find workflow traces by session ID (workflow UUID)

### View agent logs

```bash
# All agents
kubectl logs -n dapr-agents -l app.kubernetes.io/part-of=speckit -f

# Specific agent
kubectl logs -n dapr-agents deploy/speckit-planner -f

# Dapr sidecar logs
kubectl logs -n dapr-agents deploy/speckit-planner -c daprd -f
```

## Troubleshooting

### Agent stuck in CrashLoopBackOff

```bash
# Check logs
kubectl logs -n dapr-agents deploy/speckit-<agent> --previous

# Common issues:
# - Missing ANTHROPIC_API_KEY: Check secret exists
# - Dapr sidecar not ready: Wait for dapr-sidecar-injector
# - Redis unavailable: Check redis-service is running
```

### Workflow stuck in one phase

```bash
# Check current agent logs
kubectl logs -n dapr-agents deploy/speckit-<current-agent> -f

# Check Dapr pub/sub
kubectl logs -n dapr-agents deploy/speckit-<agent> -c daprd | grep "pub\|sub"

# Force state reset (for testing)
kubectl exec -n dapr-agents deploy/speckit-orchestrator -- \
  curl -X DELETE http://localhost:3500/v1.0/state/workflowstatestore/workflow:<workflow-id>
```

### Claude SDK errors

```bash
# Check API key is valid
kubectl exec -n dapr-agents deploy/speckit-specifier -- \
  python -c "import os; print(os.environ.get('ANTHROPIC_API_KEY', 'NOT SET')[:10])"

# Check network access to Anthropic API
kubectl exec -n dapr-agents deploy/speckit-specifier -- \
  curl -I https://api.anthropic.com/
```

## Architecture Verification

### Verify Dapr handles messaging (not Claude SDK)

```bash
# Watch pub/sub events
kubectl logs -n dapr-agents deploy/speckit-orchestrator -c daprd -f | grep "pub\|topic"

# You should see topic messages like:
# msg="Subscribing to topic speckit.specifier.requests"
# msg="Published message to topic speckit.orchestrator.requests"
```

### Verify Claude SDK handles AI calls

```bash
# Check Langfuse for Claude API traces
# Each agent should show claude_agent_query generations

# Or check agent logs for SDK activity
kubectl logs -n dapr-agents deploy/speckit-specifier | grep "claude\|query"
```

## Performance Benchmarks

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Spec generation | <2 min | Time from /run to spec artifact |
| Planning (parallel) | <4 min | Time from spec complete to plan complete |
| 10 concurrent workflows | No degradation | Load test with 10 parallel requests |

```bash
# Benchmark spec generation
time curl -X POST http://localhost:8000/run \
  -H "Content-Type: application/json" \
  -d '{"task": "Add user authentication"}'

# Wait for spec artifact
while ! curl -s http://localhost:8000/status/<id> | grep '"type":"spec"'; do
  sleep 5
done
```

## Next Steps

After deployment verification:

1. Run `/speckit.tasks` to generate implementation tasks
2. Use `/speckit.implement` to execute tasks
3. Monitor progress in Langfuse dashboard
