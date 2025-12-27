# CAIPE Installation Troubleshooting Guide

This document details the modifications and troubleshooting steps required to get the CAIPE (Community AI Platform Engineering) stack working on our idpBuilder-based Kubernetes cluster.

## Table of Contents

1. [Environment Overview](#environment-overview)
2. [Backstage AI Chat Icon](#backstage-ai-chat-icon)
3. [RAG Server and WebUI](#rag-server-and-webui)
4. [Azure OpenAI Configuration](#azure-openai-configuration)
5. [Neo4j Memory Configuration](#neo4j-memory-configuration)
6. [PostgreSQL Password Synchronization](#postgresql-password-synchronization)
7. [Summary of All Changes](#summary-of-all-changes)

---

## Environment Overview

- **Cluster Type**: idpBuilder (KIND-based local Kubernetes)
- **Domain**: `cnoe.localtest.me:8443`
- **Secrets Management**: HashiCorp Vault + External Secrets Operator
- **Cloud Provider**: Azure (Key Vault, Azure OpenAI)
- **GitOps**: ArgoCD with auto-sync enabled

---

## Backstage AI Chat Icon

### Problem
The AI chat icon was not appearing in the bottom-right corner of the Backstage UI.

### Root Cause
Backstage was using the standard CNOE image (`ghcr.io/cnoe-io/backstage-app:9232d633...`) which does not include the CAIPE agentForge plugin.

### Solution

#### Step 1: Disable ArgoCD Auto-Sync
ArgoCD was reverting manual changes. Temporarily disable auto-sync:

```bash
kubectl patch application -n argocd backstage --type json \
  -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
```

#### Step 2: Update Backstage Image
Switch to the CAIPE-enabled Backstage image:

```bash
kubectl set image deployment/backstage -n backstage \
  backstage=ghcr.io/suwhang-cisco/backstage-app:608f93ad3fc75cd3161d7163ba677e9ccc9caeff
```

#### Step 3: Update ConfigMap with agentForge Configuration
Add the `agentForge` section to the Backstage ConfigMap:

```yaml
# /tmp/backstage-config-updated.yaml - Add this section at the end
agentForge:
  baseUrl: ${AGENT_FORGE_URL}
  botName: CAIPE
  infoPage: https://cnoe-io.github.io/ai-platform-engineering/
  showOptions: true
  useOpenIDToken: false
  enableStreaming: true
  requestTimeout: 300
  autoReloadOnTokenExpiry: false
  userEmailMode: "none"
  headerTitle: CAIPE Distributed Multi-Agentic System
  headerSubtitle: AI Platform Engineer Assistant
  inputPlaceholder: Ask CAIPE anything...
  initialSuggestions:
    - What can you do?
    - What ArgoCD Applications are deployed?
    - List all users and groups in Backstage
    - Get my Github profile details
  thinkingMessagesInterval: 7000
  thinkingMessages:
    - "Processing query..."
    - "Contacting agents..."
    - "Analyzing data..."
    - "Assembling context..."
```

Also add the `backend.auth` section for API access:

```yaml
backend:
  auth:
    externalAccess:
    - options:
        subject: caipe-api-access
        token: ${BACKSTAGE_API_TOKEN}
      type: static
    keys:
      - secret: ${BACKSTAGE_API_TOKEN}
```

Apply the ConfigMap:

```bash
kubectl create configmap backstage-config -n backstage \
  --from-file=app-config.yaml=/tmp/backstage-config-updated.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### Step 4: Add Environment Variables
Ensure these environment variables are set in the deployment:

```bash
kubectl set env deployment/backstage -n backstage \
  AGENT_FORGE_URL=https://cnoe.localtest.me:8443/ai-platform-engineering \
  BACKSTAGE_API_TOKEN=caipe-backstage-token
```

#### Step 5: Restart Backstage
```bash
kubectl rollout restart deployment/backstage -n backstage
kubectl rollout status deployment/backstage -n backstage --timeout=120s
```

### Verification
Check that the CAIPE module is loaded:

```bash
curl -sk https://cnoe.localtest.me:8443/ 2>&1 | grep "module-caipe"
# Should show: module-caipe.7124c301.js
```

---

## RAG Server and WebUI

### Problem
RAG WebUI showed as "unreachable" and rag-server was in CrashLoopBackOff.

### Root Cause Analysis

The rag-server has a **hardcoded dependency on Azure OpenAI for embeddings**, regardless of the `LLM_PROVIDER` setting. Multiple issues were identified:

1. **Empty `AZURE_OPENAI_ENDPOINT`**: Caused `httpcore.UnsupportedProtocol: Request URL is missing an 'http://' or 'https://' protocol`
2. **Missing Azure OpenAI Deployment**: No `text-embedding-3-small` deployment existed
3. **Low Rate Limits**: Initial deployment had capacity of 1 (1000 tokens/minute)

### Solution

#### Step 1: Update Vault with Azure OpenAI Credentials

Create a script to update Vault with correct Azure OpenAI configuration:

```bash
#!/usr/bin/env bash
# /tmp/update-vault-final.sh
set -e

VAULT_TOKEN=$(kubectl get secret -n vault vault-root-token -o jsonpath='{.data.token}' | base64 -d)

pkill -f "port-forward.*vault" 2>/dev/null || true
sleep 1

kubectl port-forward -n vault svc/vault 8201:8200 &
PF_PID=$!
sleep 3

curl -s -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -d '{
    "data":{
      "LLM_PROVIDER":"openai",
      "OPENAI_API_KEY":"<your-openai-api-key>",
      "OPENAI_ENDPOINT":"https://api.openai.com/v1",
      "OPENAI_BASE_URL":"https://api.openai.com/v1",
      "OPENAI_MODEL_NAME":"gpt-4.1",
      "OPENAI_API_VERSION":"",
      "AZURE_OPENAI_API_KEY":"<your-azure-openai-api-key>",
      "AZURE_OPENAI_ENDPOINT":"https://<your-resource>.openai.azure.com",
      "AZURE_OPENAI_API_VERSION":"2024-02-01",
      "AZURE_OPENAI_DEPLOYMENT":"text-embedding-3-small",
      "AWS_ACCESS_KEY_ID":"",
      "AWS_SECRET_ACCESS_KEY":"",
      "AWS_REGION":"us-east-1",
      "AWS_BEDROCK_MODEL_ID":"",
      "AWS_BEDROCK_PROVIDER":""
    }
  }' \
  http://127.0.0.1:8201/v1/secret/data/ai-platform-engineering/global

kill $PF_PID 2>/dev/null || true
echo "Updated Vault with Azure OpenAI configuration"
```

#### Step 2: Force Sync External Secret

```bash
kubectl annotate externalsecret -n ai-platform-engineering llm-secret \
  force-sync=$(date +%s) --overwrite
```

#### Step 3: Verify Secret Values

```bash
kubectl get secret -n ai-platform-engineering llm-secret -o jsonpath='{.data.AZURE_OPENAI_ENDPOINT}' | base64 -d
# Should output: https://<your-resource>.openai.azure.com
```

#### Step 4: Restart rag-server

```bash
kubectl rollout restart deployment/rag-server -n ai-platform-engineering
kubectl rollout status deployment/rag-server -n ai-platform-engineering --timeout=60s
```

---

## Azure OpenAI Configuration

### Problem
Even with correct credentials, rag-server failed with `DeploymentNotFound` error.

### Root Cause
No embedding model deployment existed in the Azure OpenAI resource.

### Solution

#### Step 1: Set Correct Azure Subscription

```bash
az account set --subscription <your-subscription-id>
az account show --query "{subscription:name, id:id}" -o table
```

#### Step 2: Create Embedding Deployment

```bash
az cognitiveservices account deployment create \
  --name <your-azure-openai-resource> \
  --resource-group <your-resource-group> \
  --deployment-name text-embedding-3-small \
  --model-name text-embedding-3-small \
  --model-version "1" \
  --model-format OpenAI \
  --sku-capacity 120 \
  --sku-name Standard
```

**Important**: Initial deployment may have low capacity (1). Increase to at least 120 for production use.

#### Step 3: Increase Capacity (if needed)

If you encounter rate limit errors (`429 - RateLimitReached`), increase the deployment capacity:

```bash
az cognitiveservices account deployment create \
  --name <your-azure-openai-resource> \
  --resource-group <your-resource-group> \
  --deployment-name text-embedding-3-small \
  --model-name text-embedding-3-small \
  --model-version "1" \
  --model-format OpenAI \
  --sku-capacity 120 \
  --sku-name Standard
```

This provides:
- **Requests**: 120 per 10 seconds
- **Tokens**: 120,000 per minute

---

## Neo4j Memory Configuration

### Problem
Neo4j pods crashed with `Invalid memory configuration - exceeds physical memory`.

### Root Cause
Missing memory configuration parameters in Neo4j ConfigMaps.

### Solution

Patch the Neo4j ConfigMaps with explicit memory limits:

```bash
kubectl patch configmap -n ai-platform-engineering rag-neo4j-user-config \
  --type merge -p '{"data":{"server.memory.heap.max_size":"1g","server.memory.pagecache.size":"512m"}}'

kubectl patch configmap -n ai-platform-engineering rag-neo4j-ontology-user-config \
  --type merge -p '{"data":{"server.memory.heap.max_size":"1g","server.memory.pagecache.size":"512m"}}'
```

Then restart Neo4j:

```bash
kubectl rollout restart statefulset/rag-neo4j -n ai-platform-engineering
kubectl rollout restart statefulset/rag-neo4j-ontology -n ai-platform-engineering
```

---

## PostgreSQL Password Synchronization

### Problem
Backstage failed with `password authentication failed for user "backstage"`.

### Root Cause
PostgreSQL PVC was initialized before External Secret synced, causing password mismatch between what PostgreSQL was initialized with and what Backstage was using.

### Solution

Force reinitialize PostgreSQL with the correct password:

```bash
# Delete the PostgreSQL pod
kubectl delete pod -n backstage postgresql-0

# Remove the finalizer and delete the PVC
kubectl patch pvc -n backstage data-postgresql-0 \
  -p '{"metadata":{"finalizers":null}}'
kubectl delete pvc -n backstage data-postgresql-0

# The StatefulSet will recreate the pod with a new PVC
# PostgreSQL will reinitialize with the correct password from the secret
```

---

## Summary of All Changes

### Vault Secret Updates

The following secrets were configured in Vault at path `secret/ai-platform-engineering/global`:

| Key | Value | Notes |
|-----|-------|-------|
| `LLM_PROVIDER` | `openai` | Primary LLM provider |
| `OPENAI_API_KEY` | `sk-proj-...` | OpenAI API key |
| `OPENAI_ENDPOINT` | `https://api.openai.com/v1` | OpenAI endpoint |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | Required by langchain |
| `OPENAI_MODEL_NAME` | `gpt-4.1` | Model for chat completions |
| `AZURE_OPENAI_API_KEY` | `Azdi7X...` | Azure OpenAI key |
| `AZURE_OPENAI_ENDPOINT` | `https://<resource>.openai.azure.com` | **Required for embeddings** |
| `AZURE_OPENAI_API_VERSION` | `2024-02-01` | API version |
| `AZURE_OPENAI_DEPLOYMENT` | `text-embedding-3-small` | Embedding deployment name |

### Azure Resources Created

| Resource | Type | Configuration |
|----------|------|---------------|
| `text-embedding-3-small` | Azure OpenAI Deployment | Model: text-embedding-3-small, Capacity: 120, SKU: Standard |

### Kubernetes Modifications

| Resource | Namespace | Change |
|----------|-----------|--------|
| Backstage Deployment | `backstage` | Image changed to `ghcr.io/suwhang-cisco/backstage-app:608f93ad...` |
| Backstage ConfigMap | `backstage` | Added `agentForge` and `backend.auth` sections |
| Backstage Deployment | `backstage` | Added `AGENT_FORGE_URL` and `BACKSTAGE_API_TOKEN` env vars |
| Neo4j ConfigMaps | `ai-platform-engineering` | Added `heap.max_size=1g` and `pagecache.size=512m` |
| ArgoCD Application | `argocd` | Disabled auto-sync for `backstage` application |

### Access URLs

| Service | URL |
|---------|-----|
| Backstage (with AI Chat) | https://cnoe.localtest.me:8443/ |
| RAG WebUI | https://rag-webui.cnoe.localtest.me:8443/ |
| ArgoCD | https://cnoe.localtest.me:8443/argocd |
| Supervisor Agent API | https://cnoe.localtest.me:8443/ai-platform-engineering |

---

## Known Issues and Workarounds

### 1. rag-server Hardcoded Azure OpenAI for Embeddings
**Issue**: The rag-server always uses Azure OpenAI for embeddings regardless of `LLM_PROVIDER` setting.

**Workaround**: Must configure valid Azure OpenAI credentials and create an embedding deployment even if using regular OpenAI for chat completions.

### 2. ArgoCD Reverts Manual Changes
**Issue**: ArgoCD auto-sync reverts manual kubectl changes.

**Workaround**: Either:
- Disable auto-sync: `kubectl patch application -n argocd <app> --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'`
- Update source manifests in Gitea repository

### 3. External Secret Overwrites Manual Secret Patches
**Issue**: ESO continuously reconciles secrets, overwriting manual patches.

**Workaround**: Update the source (Vault) instead of patching Kubernetes secrets directly.

### 4. Shell Command Substitution Issues
**Issue**: Some bash commands with `$()` syntax fail in certain environments.

**Workaround**: Write values to temporary files first, then use them:
```bash
# Instead of: VAR=$(command)
command > /tmp/output.txt
cat /tmp/output.txt  # use the value
```

---

## Verification Checklist

After completing all steps, verify:

- [ ] Backstage pod is Running (1/1)
- [ ] AI chat icon appears in Backstage bottom-right corner
- [ ] rag-server pod is Running (1/1) with no restarts
- [ ] RAG WebUI loads at https://rag-webui.cnoe.localtest.me:8443
- [ ] Neo4j pods are Running (both rag-neo4j and rag-neo4j-ontology)
- [ ] Milvus pods are Running (all 5 components)
- [ ] Supervisor agent responds at /ai-platform-engineering endpoint

```bash
# Quick verification commands
kubectl get pods -n backstage
kubectl get pods -n ai-platform-engineering | grep -E "rag-server|neo4j|milvus|supervisor"
curl -sk https://cnoe.localtest.me:8443/ | grep "module-caipe"
curl -sk https://rag-webui.cnoe.localtest.me:8443/ | head -5
curl -sk https://cnoe.localtest.me:8443/ai-platform-engineering/health
```
