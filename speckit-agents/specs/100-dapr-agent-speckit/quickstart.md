# Quickstart: SpecKit Agent Observability

**Feature ID:** 100-dapr-agent-speckit-observability
**Date:** 2025-12-03

---

## Prerequisites

Before deploying the observability stack:

1. **Cluster running** with Dapr, Tailscale, and SpecKit agents deployed
2. **Azure Key Vault** access configured for External Secrets
3. **CDK8s environment** set up (`cd cdk8s && npm install`)

---

## Step 1: Add Secrets to Azure Key Vault

Generate and add the following secrets:

```bash
# Generate secrets
NEXTAUTH_SECRET=$(openssl rand -base64 32)
SALT=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -base64 16)

# Add to Azure Key Vault (replace with your vault name)
az keyvault secret set --vault-name <vault-name> --name LANGFUSE-POSTGRES-USER --value "langfuse"
az keyvault secret set --vault-name <vault-name> --name LANGFUSE-POSTGRES-PASSWORD --value "$POSTGRES_PASSWORD"
az keyvault secret set --vault-name <vault-name> --name LANGFUSE-NEXTAUTH-SECRET --value "$NEXTAUTH_SECRET"
az keyvault secret set --vault-name <vault-name> --name LANGFUSE-SALT --value "$SALT"
az keyvault secret set --vault-name <vault-name> --name LANGFUSE-ENCRYPTION-KEY --value "$ENCRYPTION_KEY"

# API keys will be generated after Langfuse is running (Step 5)
```

---

## Step 2: Synthesize CDK8s Charts

```bash
cd ~/stacks/cdk8s
npx ts-node main-v2.ts
```

Expected output: New packages in `dist/`:
- `observability-namespace/`
- `observability-secrets/`
- `jaeger/`
- `langfuse-postgres/`
- `langfuse/`
- `dapr-tracing-config/`

---

## Step 3: Deploy with cluster-update

```bash
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update
```

Monitor deployment:
```bash
# Watch observability pods
kubectl get pods -n observability -w

# Expected pods:
# jaeger-xxx           1/1     Running
# langfuse-postgres-xxx  1/1   Running
# langfuse-xxx         1/1     Running
```

---

## Step 4: Verify Jaeger

```bash
# Port-forward to Jaeger UI
kubectl port-forward -n observability svc/jaeger-query 16686:16686 &

# Open browser
open http://localhost:16686

# Or via ingress (if DNS configured)
open https://jaeger.cnoe.localtest.me:8443
```

**Verification:**
1. Jaeger UI loads
2. After submitting a workflow, services appear in dropdown
3. Traces show spans across agents

---

## Step 5: Set Up Langfuse

```bash
# Port-forward to Langfuse
kubectl port-forward -n observability svc/langfuse 3000:3000 &

# Open browser
open http://localhost:3000
```

**Initial Setup:**
1. Click "Sign Up" to create admin account
2. Create a new project (e.g., "SpecKit")
3. Go to Settings → API Keys
4. Create new API key pair
5. Add keys to Azure Key Vault:

```bash
az keyvault secret set --vault-name <vault-name> --name LANGFUSE-PUBLIC-KEY --value "pk_xxx"
az keyvault secret set --vault-name <vault-name> --name LANGFUSE-SECRET-KEY --value "sk_xxx"
```

6. Restart agents to pick up new secrets:
```bash
kubectl rollout restart deployment -n dapr-agents -l app.kubernetes.io/part-of=speckit-agents
```

---

## Step 6: Test Observability

```bash
# Submit a test workflow
kubectl run curl-test --rm -i --restart=Never --image=curlimages/curl -- \
  curl -X POST http://speckit-orchestrator.dapr-agents.svc.cluster.local:8000/run \
  -H "Content-Type: application/json" \
  -d '{"task": "Create a simple hello world function"}'
```

**Verify in Jaeger:**
1. Open http://localhost:16686
2. Select service: `orchestrator` or `specifier`
3. Click "Find Traces"
4. View trace timeline showing all agent interactions

**Verify in Langfuse:**
1. Open http://localhost:3000
2. Go to "Traces" tab
3. Filter by session (workflow ID)
4. View LLM prompts, responses, and token usage

---

## Step 7: Remote Access via Tailscale

From any Tailscale-connected device:

```bash
# Get Tailscale hostnames
tailscale status | grep jaeger
tailscale status | grep langfuse

# Access UIs (replace with your tailnet)
open https://jaeger.tail286401.ts.net
open https://langfuse.tail286401.ts.net
```

---

## Troubleshooting

### Jaeger not receiving traces

```bash
# Check Dapr sidecar tracing config
kubectl describe pod -n dapr-agents -l app=speckit-orchestrator | grep -A5 "dapr.io/config"

# Verify tracing config exists
kubectl get configuration -n dapr-agents speckit-tracing -o yaml

# Check Jaeger collector logs
kubectl logs -n observability -l app=jaeger --tail=50
```

### Langfuse not showing generations

```bash
# Check agent has Langfuse env vars
kubectl exec -n dapr-agents deploy/speckit-orchestrator -c orchestrator -- env | grep LANGFUSE

# Verify Langfuse connectivity
kubectl exec -n dapr-agents deploy/speckit-orchestrator -c orchestrator -- \
  curl -s http://langfuse.observability.svc.cluster.local:3000/api/health

# Check agent logs for Langfuse errors
kubectl logs -n dapr-agents -l app=speckit-orchestrator -c orchestrator | grep -i langfuse
```

### PostgreSQL connection issues

```bash
# Check PostgreSQL is running
kubectl get pods -n observability -l app=langfuse-postgres

# Check connection from Langfuse
kubectl logs -n observability -l app=langfuse --tail=100 | grep -i database

# Verify secret exists
kubectl get secret -n observability langfuse-postgres-credentials -o yaml
```

### Remote access not working

```bash
# Check Tailscale services exist
kubectl get svc -n ingress-nginx | grep ts-

# Verify Tailscale operator
kubectl logs -n tailscale -l app.kubernetes.io/name=tailscale-operator --tail=50

# Check Tailscale admin console for devices
# https://login.tailscale.com/admin/machines
```

---

## Quick Reference

| Service | Local URL | Remote URL | Port |
|---------|-----------|------------|------|
| Jaeger UI | http://localhost:16686 | https://jaeger.{tailnet}.ts.net | 16686 |
| Jaeger Collector | - | - | 9411 (Zipkin) |
| Langfuse UI | http://localhost:3000 | https://langfuse.{tailnet}.ts.net | 3000 |
| PostgreSQL | - | - | 5432 |

| Command | Description |
|---------|-------------|
| `kubectl port-forward -n observability svc/jaeger-query 16686:16686` | Local Jaeger access |
| `kubectl port-forward -n observability svc/langfuse 3000:3000` | Local Langfuse access |
| `kubectl logs -n observability -l app=jaeger` | Jaeger logs |
| `kubectl logs -n observability -l app=langfuse` | Langfuse logs |
