# Quickstart: Deploy kagent and kgateway with Agentgateway

**Date**: November 17, 2025
**Feature**: 008-install-kagent-agentgateway-kubernetes
**Estimated Time**: 30-45 minutes

## Prerequisites

Before starting, ensure you have:

- [ ] Kubernetes cluster v1.26+ (Kind for local dev)
- [ ] kubectl configured and connected to cluster
- [ ] Helm v3.10+ (for OCI registry support)
- [ ] ArgoCD installed and accessible
- [ ] External Secrets Operator configured
- [ ] ClusterSecretStore for Azure Key Vault
- [ ] Azure Key Vault with LLM API keys:
  - `OPENAI-API-KEY`
  - `ANTHROPIC-API-KEY`
  - `GEMINI-API-KEY`
- [ ] IdpBuilder available for deployment
- [ ] 1Password CLI (optional, for ArgoCD auth)

## Quick Verification Commands

```bash
# Verify cluster access
kubectl cluster-info

# Verify Helm version
helm version --short

# Verify ArgoCD
kubectl get pods -n argocd

# Verify ESO
kubectl get pods -n external-secrets

# Verify ClusterSecretStore
kubectl get clustersecretstore azure-keyvault-store
```

---

## Step 1: Deploy CDK8s Charts

### 1.1 Synthesize Charts

```bash
cd cdk8s
npx ts-node main-v2.ts
```

**Expected Output**:
```
Synthesizing packages...
✓ gateway-api-crds
✓ kgateway-crds
✓ kgateway
✓ kagent-crds
✓ kagent
✓ kagent-secrets
✓ kagent-agents
Done! Packages written to dist/
```

### 1.2 Deploy via IdpBuilder

```bash
# Deploy all packages
idpbuilder create --package cdk8s/dist/

# Or deploy specific packages in order
idpbuilder create --package cdk8s/dist/gateway-api-crds
idpbuilder create --package cdk8s/dist/kgateway-crds
idpbuilder create --package cdk8s/dist/kgateway
idpbuilder create --package cdk8s/dist/kagent-crds
idpbuilder create --package cdk8s/dist/kagent
idpbuilder create --package cdk8s/dist/kagent-secrets
idpbuilder create --package cdk8s/dist/kagent-agents
```

---

## Step 2: Verify Deployment

### 2.1 Check ArgoCD Applications

```bash
# List all kagent/kgateway applications
argocd app list --insecure | grep -E 'kgateway|kagent|gateway-api'

# Expected: All applications show "Synced" and "Healthy"
```

**Expected Output**:
```
argocd/gateway-api-crds    default  Synced  Healthy
argocd/kgateway-crds       default  Synced  Healthy
argocd/kgateway            default  Synced  Healthy
argocd/kagent-crds         default  Synced  Healthy
argocd/kagent              default  Synced  Healthy
argocd/kagent-secrets      default  Synced  Healthy
argocd/kagent-agents       default  Synced  Healthy
```

### 2.2 Check Pod Status

```bash
# kgateway pods
kubectl get pods -n kgateway-system
# Expected: control plane and gateway proxy Running

# kagent pods
kubectl get pods -n kagent
# Expected: controller, ui, kmcp-controller Running
```

### 2.3 Check CRDs

```bash
# Gateway API CRDs
kubectl get crds | grep gateway.networking.k8s.io

# kgateway CRDs
kubectl get crds | grep kgateway

# kagent CRDs
kubectl get crds | grep kagent.dev
```

**Expected CRDs**:
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `agents.kagent.dev`
- `modelconfigs.kagent.dev`
- `mcpservers.kagent.dev`

### 2.4 Check External Secrets

```bash
# Verify ExternalSecret synced
kubectl get externalsecret -n kagent kagent-llm-providers

# Expected: SecretSynced condition
# STATUS: SecretSynced

# Verify secret created
kubectl get secret -n kagent kagent-llm-providers

# Check secret keys
kubectl get secret -n kagent kagent-llm-providers -o jsonpath='{.data}' | jq -r 'keys'
# Expected: ["ANTHROPIC_API_KEY", "GEMINI_API_KEY", "OPENAI_API_KEY"]
```

---

## Step 3: Access kagent Dashboard

### Option 1: Via Ingress (Domain-based routing)

```bash
# Open in browser
open https://kagent.cnoe.localtest.me:8443
```

### Option 2: Via Port-Forward

```bash
kubectl port-forward -n kagent svc/kagent-ui 8080:8080 &
open http://localhost:8080
```

**Expected**: kagent dashboard loads with agent management interface

---

## Step 4: Test AI Agent

### 4.1 Create ModelConfig

```bash
# Verify ModelConfig exists (created by Helm chart)
kubectl get modelconfig -n kagent

# Check status
kubectl get modelconfig -n kagent -o wide
# Expected: Ready=True
```

### 4.2 Create Test Agent

```yaml
# test-agent.yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: test-agent
  namespace: kagent
spec:
  type: Declarative
  description: "Test agent for verification"
  systemMessage: "You are a helpful assistant for testing kagent deployment."
  modelConfig:
    ref: default-openai  # Reference to ModelConfig
```

```bash
kubectl apply -f test-agent.yaml
kubectl get agent -n kagent test-agent
# Expected: Ready=True
```

### 4.3 Test Agent Response (via Dashboard)

1. Open kagent dashboard
2. Select "test-agent"
3. Send message: "Hello, can you confirm you're working?"
4. Wait for response (should be < 30 seconds)

---

## Step 5: Verify Agentgateway Integration

### 5.1 Create Gateway Resource

```yaml
# mcp-gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: mcp-gateway
  namespace: kgateway-system
spec:
  gatewayClassName: kgateway
  listeners:
    - name: http
      protocol: HTTP
      port: 8080
```

```bash
kubectl apply -f mcp-gateway.yaml
kubectl get gateway -n kgateway-system mcp-gateway
# Expected: Programmed=True
```

### 5.2 Check Gateway Status

```bash
kubectl describe gateway -n kgateway-system mcp-gateway
# Look for:
# - Programmed: True
# - Accepted: True
```

---

## Step 6: Verify with 1Password ArgoCD Auth

```bash
# Authenticate ArgoCD CLI via 1Password
eval $(op signin)
export ARGOCD_AUTH_TOKEN=$(op read "op://vault/argocd/token")

# Check all applications
argocd app list --insecure

# Detailed health check
argocd app get argocd/kagent --insecure
argocd app get argocd/kgateway --insecure

# Expected: All resources healthy, no sync errors
```

---

## Troubleshooting

### Issue: ArgoCD Application stuck in Progressing

```bash
# Check sync status
argocd app get argocd/<app-name> --insecure --show-operation

# Force refresh
argocd app refresh argocd/<app-name> --insecure

# Check pod events
kubectl describe pod -n <namespace> <pod-name>
```

### Issue: External Secret not syncing

```bash
# Check ESO operator logs
kubectl logs -n external-secrets deploy/external-secrets

# Check ClusterSecretStore status
kubectl describe clustersecretstore azure-keyvault-store

# Verify Azure Key Vault keys exist
az keyvault secret list --vault-name <vault-name>
```

### Issue: kagent controller CrashLoopBackOff

```bash
# Check controller logs
kubectl logs -n kagent deploy/kagent-controller

# Common causes:
# - Missing LLM API key secret
# - Invalid ModelConfig reference
# - Database initialization failure
```

### Issue: kgateway pods not starting

```bash
# Check Gateway API CRDs installed
kubectl get crds | grep gateway.networking.k8s.io

# Check kgateway-crds application
argocd app get argocd/kgateway-crds --insecure

# Verify namespace exists
kubectl get namespace kgateway-system
```

---

## Success Criteria Checklist

- [ ] Gateway API CRDs installed (v1.4.0)
- [ ] kgateway-system namespace exists
- [ ] kgateway control plane Running
- [ ] kgateway gateway proxy Running
- [ ] kagent namespace exists
- [ ] kagent controller Running
- [ ] kagent UI Running
- [ ] kmcp controller Running
- [ ] ExternalSecret synced (kagent-llm-providers)
- [ ] ModelConfig resources Ready
- [ ] Agent resources Ready
- [ ] ArgoCD shows all applications Synced/Healthy
- [ ] kagent dashboard accessible
- [ ] Test agent responds to queries
- [ ] Gateway resource Programmed

---

## Next Steps

1. **Configure MCP Traffic Routing**: Create HTTPRoute resources for MCP servers
2. **Enable OpenTelemetry**: Configure GatewayParameters for tracing
3. **Deploy Production Agents**: Create domain-specific agents (Kubernetes, Monitoring, etc.)
4. **Set Up Monitoring**: Integrate with existing observability stack
5. **Configure RBAC**: Fine-tune agent permissions with CEL-based policies

---

## Cleanup

```bash
# Remove test agent
kubectl delete agent -n kagent test-agent

# Remove test gateway
kubectl delete gateway -n kgateway-system mcp-gateway

# Full cleanup (removes all kagent/kgateway resources)
argocd app delete argocd/kagent-agents --insecure
argocd app delete argocd/kagent-secrets --insecure
argocd app delete argocd/kagent --insecure
argocd app delete argocd/kagent-crds --insecure
argocd app delete argocd/kgateway --insecure
argocd app delete argocd/kgateway-crds --insecure
argocd app delete argocd/gateway-api-crds --insecure

# Delete namespaces
kubectl delete namespace kagent
kubectl delete namespace kgateway-system
```

---

## References

- [kagent Documentation](https://kagent.dev/docs/)
- [kgateway Documentation](https://kgateway.dev/docs/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [External Secrets Operator](https://external-secrets.io/)
- [ArgoCD Helm Chart Support](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
