# Quickstart: SpecKit Multi-Agent Workflow System

**Branch**: `100-dapr-agent-speckit`
**Date**: 2025-12-03

## Overview

This quickstart guides you through deploying and using the SpecKit multi-agent workflow system for automated feature development.

## Prerequisites

- Kubernetes cluster with Dapr runtime installed
- ArgoCD for GitOps deployment
- Redis for state and pub/sub
- LLM API keys (Anthropic) in cluster secrets

**Verify infrastructure:**
```bash
# Check Dapr runtime
kubectl get pods -n dapr-system
# Expected: All pods Running

# Check Dapr components
kubectl get components -n dapr-agents
# Expected: agentregistrystore, anthropic, memorystore, messagepubsub, workflowstatestore

# Check secrets
kubectl get secret -n dapr-agents dapr-agents-llm-providers
# Expected: Secret exists with ANTHROPIC_API_KEY
```

## Deployment

### Option 1: ArgoCD (Recommended)

The infrastructure is already deployed via ArgoCD applications:

```bash
# Check application status
argocd app list --insecure | grep -E "dapr|speckit"
# Expected: All apps Synced/Healthy (speckit-agents may be Progressing until images built)
```

### Option 2: Build and Push Agent Image

If you need to build the agent container image:

```bash
# Build the multi-agent image
cd speckit-agents/
docker build -t ghcr.io/pittampalliorg/speckit-agents:latest .

# Push to registry
docker push ghcr.io/pittampalliorg/speckit-agents:latest

# Restart deployments to pull new image
kubectl rollout restart deployment -n dapr-agents -l app.kubernetes.io/part-of=speckit
```

## Usage

### Start a Workflow via HTTP

Send a feature request to the orchestrator:

```bash
# Port-forward to orchestrator
kubectl port-forward -n dapr-agents svc/speckit-orchestrator 8000:8000 &

# Submit a feature request
curl -X POST http://localhost:8000/run \
  -H "Content-Type: application/json" \
  -d '{"task": "Add user authentication with OAuth2 support and role-based access control"}'

# Response:
# {"instance_id": "abc123...", "status": "pending", "status_url": "/status/abc123..."}
```

### Start a Workflow via Pub/Sub

Publish a TriggerAction message directly to the orchestrator topic:

```bash
# Using Dapr CLI (requires dapr installed)
dapr publish \
  --publish-app-id speckit-orchestrator \
  --pubsub messagepubsub \
  --topic speckit.orchestrator.requests \
  --data '{"task": "Add dark mode toggle to application settings"}'

# Or using kubectl with a test pod
kubectl run pubsub-client --rm -it --image=python:3.11 -- bash
pip install dapr
python -c "
from dapr.clients import DaprClient
with DaprClient() as d:
    d.publish_event(
        pubsub_name='messagepubsub',
        topic_name='speckit.orchestrator.requests',
        data='{\"task\": \"Add dark mode toggle\"}',
        data_content_type='application/json',
        publish_metadata={'cloudevent.type': 'TriggerAction'}
    )
"
```

### Monitor Workflow Progress

```bash
# Check workflow status
curl http://localhost:8000/status/{workflow_id}

# Watch agent logs
kubectl logs -n dapr-agents -l app.kubernetes.io/part-of=speckit -f

# Check workflow state in Redis
kubectl exec -n dapr-agents deploy/dapr-agents-redis -- redis-cli keys "speckit:*"
```

### View Generated Artifacts

Artifacts are stored in the shared volume at `/artifacts/{workflow_id}/`:

```bash
# List artifacts for a workflow
kubectl exec -n dapr-agents deploy/speckit-orchestrator -- ls -la /artifacts/{workflow_id}/

# Read generated spec.md
kubectl exec -n dapr-agents deploy/speckit-orchestrator -- cat /artifacts/{workflow_id}/spec.md
```

## Agent Communication Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        User Request                                  │
│                    "Add user authentication"                         │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     ORCHESTRATOR (8000)                              │
│  • Receives TriggerAction                                            │
│  • Queries agent registry for team "speckit"                         │
│  • Uses LLM to select appropriate agent                              │
│  • Routes to specifier for new workflows                             │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ speckit.specifier.requests
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      SPECIFIER (8001)                                │
│  • Generates spec.md from feature description                        │
│  • Uses SpecKit template format                                      │
│  • Publishes completion → orchestrator routes to planner             │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ speckit.planner.requests
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       PLANNER (8002)                                 │
│  • Reads spec.md                                                     │
│  • Generates: plan.md, research.md, data-model.md, contracts/        │
│  • Publishes completion → orchestrator routes to task-generator      │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ speckit.task-generator.requests
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   TASK GENERATOR (8003)                              │
│  • Reads plan.md and related artifacts                               │
│  • Generates tasks.md with phased, ordered tasks                     │
│  • Publishes completion → orchestrator routes to implementer         │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ speckit.implementer.requests
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    IMPLEMENTER (8004)                                │
│  • Reads tasks.md                                                    │
│  • Executes tasks in dependency order                                │
│  • Generates source code and tests                                   │
│  • Updates task status in tasks.md                                   │
└─────────────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Agents Not Starting

```bash
# Check pod status
kubectl get pods -n dapr-agents -l app.kubernetes.io/part-of=speckit

# Check for image pull errors
kubectl describe pod -n dapr-agents -l app=speckit-orchestrator

# Check Dapr sidecar injection
kubectl get pods -n dapr-agents -o jsonpath='{.items[*].spec.containers[*].name}' | tr ' ' '\n' | sort | uniq
# Should show both agent name AND daprd
```

### Messages Not Being Processed

```bash
# Check Dapr subscriptions
kubectl exec -n dapr-agents deploy/speckit-orchestrator -c daprd -- curl http://localhost:3500/v1.0/metadata

# Check pub/sub component
kubectl get component -n dapr-agents messagepubsub -o yaml

# Test pub/sub directly
kubectl exec -n dapr-agents deploy/speckit-orchestrator -c daprd -- \
  curl -X POST http://localhost:3500/v1.0/publish/messagepubsub/speckit.orchestrator.requests \
  -H "Content-Type: application/json" \
  -d '{"task": "test"}'
```

### LLM Not Responding

```bash
# Check conversation component
kubectl get component -n dapr-agents anthropic -o yaml

# Verify API key
kubectl get secret -n dapr-agents dapr-agents-llm-providers -o jsonpath='{.data.ANTHROPIC_API_KEY}' | base64 -d

# Check agent logs for LLM errors
kubectl logs -n dapr-agents deploy/speckit-orchestrator | grep -i "anthropic\|llm\|error"
```

## Next Steps

1. **Build the agent container image** with Python agent code
2. **Test the complete workflow** with a sample feature request
3. **Monitor with Dapr Dashboard**: `kubectl port-forward -n dapr-system svc/dapr-dashboard 8080:8080`
4. **Add custom tools** to agents for file system access, git operations, etc.
