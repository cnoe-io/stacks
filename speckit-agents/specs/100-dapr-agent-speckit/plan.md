# Implementation Plan: SpecKit Agent Observability

**Feature ID:** 100-dapr-agent-speckit-observability
**Date:** 2025-12-03
**Branch:** 100-dapr-agent-speckit

---

## Technical Context

| Aspect | Details |
|--------|---------|
| **Platform** | Kubernetes (Kind cluster), Dapr v1.16+, CDK8s TypeScript |
| **Tracing Backend** | Jaeger v2.12.0 all-in-one with Badger storage |
| **LLM Observability** | Langfuse v3.123.1 self-hosted with PostgreSQL |
| **Access Methods** | nginx Ingress (local), Tailscale LoadBalancer (remote) |
| **Namespace** | `observability` (new) |
| **Storage** | PVC for Jaeger (10Gi), PVC for PostgreSQL (20Gi) |

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES CLUSTER                            │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    observability namespace                       │ │
│  │  ┌─────────────┐    ┌─────────────┐    ┌──────────────────────┐ │ │
│  │  │   Jaeger    │    │  Langfuse   │    │    PostgreSQL        │ │ │
│  │  │ all-in-one  │    │   Server    │    │   (for Langfuse)     │ │ │
│  │  │             │    │             │    │                      │ │ │
│  │  │ UI: 16686   │    │ UI: 3000    │    │ Port: 5432           │ │ │
│  │  │ Zipkin:9411 │    │             │    │ PVC: 20Gi            │ │ │
│  │  │ PVC: 10Gi   │    │             │    │                      │ │ │
│  │  └──────▲──────┘    └──────▲──────┘    └──────────▲───────────┘ │ │
│  │         │                  │                      │             │ │
│  └─────────┼──────────────────┼──────────────────────┼─────────────┘ │
│            │                  │                      │               │
│  ┌─────────┼──────────────────┼──────────────────────┼─────────────┐ │
│  │         │   dapr-agents    │         namespace    │             │ │
│  │  ┌──────┴───────┐   ┌──────┴───────┐   ┌─────────┴──────────┐  │ │
│  │  │ Dapr Sidecar │   │ Agent Code   │   │  Dapr Components   │  │ │
│  │  │              │   │              │   │                    │  │ │
│  │  │ Zipkin       │   │ Langfuse SDK │   │ tracing-config     │  │ │
│  │  │ Exporter     │   │ @observe()   │   │ (Configuration)    │  │ │
│  │  └──────────────┘   └──────────────┘   └────────────────────┘  │ │
│  │       ▲                    │                                    │ │
│  │       │                    │                                    │ │
│  │  ┌────┴────────────────────┴────┐                              │ │
│  │  │     SpecKit Agents (x5)      │                              │ │
│  │  │  orchestrator, specifier,    │                              │ │
│  │  │  planner, task-gen, impl     │                              │ │
│  │  └──────────────────────────────┘                              │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    ingress-nginx namespace                       │ │
│  │  ┌─────────────────────────────────────────────────────────────┐│ │
│  │  │                   Ingress Controller                        ││ │
│  │  │  jaeger.cnoe.localtest.me:8443 → jaeger:16686               ││ │
│  │  │  langfuse.cnoe.localtest.me:8443 → langfuse:3000            ││ │
│  │  └─────────────────────────────────────────────────────────────┘│ │
│  │  ┌─────────────────────────────────────────────────────────────┐│ │
│  │  │              Tailscale LoadBalancer Services                ││ │
│  │  │  ts-jaeger-ingress → ingress-nginx (hostname: jaeger)       ││ │
│  │  │  ts-langfuse-ingress → ingress-nginx (hostname: langfuse)   ││ │
│  │  └─────────────────────────────────────────────────────────────┘│ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Infrastructure (CDK8s Charts)

#### 1.1 Observability Namespace Chart

**File:** `cdk8s/charts/infra/observability-namespace-chart.ts`

**Purpose:** Create namespace with proper labels for observability stack.

**Resources:**
- Namespace: `observability`
- Labels: `app.kubernetes.io/part-of: observability`

**Sync Wave:** -70

---

#### 1.2 Jaeger Chart

**File:** `cdk8s/charts/infra/jaeger-chart.ts`

**Purpose:** Deploy Jaeger all-in-one with Badger persistent storage.

**Resources:**
| Resource | Name | Details |
|----------|------|---------|
| PersistentVolumeClaim | jaeger-badger-pvc | 10Gi, ReadWriteOnce |
| Deployment | jaeger | all-in-one:2.12.0, 1 replica |
| Service | jaeger-query | ClusterIP, port 16686 |
| Service | jaeger-collector | ClusterIP, port 9411 (Zipkin) |
| Ingress | jaeger | jaeger.cnoe.localtest.me → jaeger-query:16686 |

**Environment Variables:**
```yaml
SPAN_STORAGE_TYPE: badger
BADGER_EPHEMERAL: "false"
BADGER_DIRECTORY_KEY: /badger/key
BADGER_DIRECTORY_VALUE: /badger/value
BADGER_SPAN_STORAGE_TTL: 168h
```

**Sync Wave:** -65

---

#### 1.3 Langfuse PostgreSQL Chart

**File:** `cdk8s/charts/infra/langfuse-postgres-chart.ts`

**Purpose:** Deploy PostgreSQL instance for Langfuse.

**Resources:**
| Resource | Name | Details |
|----------|------|---------|
| PersistentVolumeClaim | langfuse-postgres-pvc | 20Gi, ReadWriteOnce |
| Deployment | langfuse-postgres | postgres:16-alpine, 1 replica |
| Service | langfuse-postgres | ClusterIP, port 5432 |
| Secret | langfuse-postgres-credentials | username, password |

**Sync Wave:** -65

---

#### 1.4 Langfuse Chart

**File:** `cdk8s/charts/infra/langfuse-chart.ts`

**Purpose:** Deploy Langfuse server with PostgreSQL connection.

**Resources:**
| Resource | Name | Details |
|----------|------|---------|
| Deployment | langfuse | langfuse:3.123.1, 1 replica |
| Service | langfuse | ClusterIP, port 3000 |
| Ingress | langfuse | langfuse.cnoe.localtest.me → langfuse:3000 |

**Environment Variables:**
```yaml
DATABASE_URL: postgresql://langfuse:${password}@langfuse-postgres:5432/langfuse
NEXTAUTH_URL: https://langfuse.cnoe.localtest.me:8443
NEXTAUTH_SECRET: ${from-secret}
SALT: ${from-secret}
ENCRYPTION_KEY: ${from-secret}
```

**Sync Wave:** -60

---

#### 1.5 Observability Secrets Chart

**File:** `cdk8s/charts/secrets/observability-secrets-chart.ts`

**Purpose:** Sync secrets from Azure Key Vault.

**ExternalSecrets:**
| Secret | Keys |
|--------|------|
| langfuse-postgres-credentials | POSTGRES_USER, POSTGRES_PASSWORD |
| langfuse-auth | NEXTAUTH_SECRET, SALT, ENCRYPTION_KEY |
| langfuse-api | PUBLIC_KEY, SECRET_KEY (for SDK) |

**Sync Wave:** -75

---

#### 1.6 Dapr Tracing Configuration Chart

**File:** `cdk8s/charts/infra/dapr-tracing-config-chart.ts`

**Purpose:** Configure Dapr to emit traces to Jaeger.

**Resources:**
```yaml
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: speckit-tracing
  namespace: dapr-agents
spec:
  tracing:
    samplingRate: "1"
    zipkin:
      endpointAddress: "http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans"
```

**Sync Wave:** -55 (after Jaeger is ready)

---

#### 1.7 Update Tailscale Publish Chart

**File:** `cdk8s/charts/platform/ingress-tailscale-publish-chart.ts`

**Purpose:** Add Jaeger and Langfuse to Tailscale-exposed services.

**Changes:**
```typescript
const HOSTS: HostSpec[] = [
  // ... existing hosts ...
  { name: 'jaeger', hostname: 'jaeger' },
  { name: 'langfuse', hostname: 'langfuse' },
];
```

---

### Phase 2: Agent Instrumentation

#### 2.1 Add Langfuse Dependency

**File:** `speckit-agents/requirements.txt`

```text
langfuse>=3.10.0
```

---

#### 2.2 Create Observability Module

**File:** `speckit-agents/src/common/observability.py`

**Purpose:** Centralized observability configuration.

```python
"""Observability configuration for SpecKit agents."""

import os
from langfuse import Langfuse
from langfuse.decorators import observe, langfuse_context

# Initialize Langfuse client
_langfuse = None

def get_langfuse() -> Langfuse:
    """Get or create Langfuse client singleton."""
    global _langfuse
    if _langfuse is None:
        _langfuse = Langfuse(
            public_key=os.environ.get("LANGFUSE_PUBLIC_KEY"),
            secret_key=os.environ.get("LANGFUSE_SECRET_KEY"),
            host=os.environ.get("LANGFUSE_HOST", "http://langfuse.observability.svc.cluster.local:3000"),
        )
    return _langfuse

def set_workflow_context(workflow_id: str, agent_name: str):
    """Set Langfuse context for current workflow."""
    langfuse_context.update_current_observation(
        session_id=workflow_id,
        user_id=agent_name,
        metadata={"agent_name": agent_name}
    )
```

---

#### 2.3 Update Agent Base Class

**File:** `speckit-agents/src/agents/base.py`

**Changes:**
- Import observability module
- Wrap LLM calls with `@observe()` decorator
- Pass workflow_id to Langfuse context

---

#### 2.4 Update Agent Deployments

**File:** `cdk8s/charts/apps/speckit-agents-chart.ts`

**Changes:**
- Add `dapr.io/config: "speckit-tracing"` annotation
- Add Langfuse environment variables from secrets

---

### Phase 3: Configuration Updates

#### 3.1 Update applications.ts

**File:** `cdk8s/config/applications.ts`

**New Applications:**
```typescript
// Observability namespace
{
  name: 'observability-namespace',
  namespace: 'observability',
  chart: { type: 'ObservabilityNamespaceChart' },
  argocd: { syncWave: '-70' }
},

// Observability secrets
{
  name: 'observability-secrets',
  namespace: 'observability',
  chart: { type: 'ObservabilitySecretsChart' },
  argocd: { syncWave: '-75' }
},

// Jaeger
{
  name: 'jaeger',
  namespace: 'observability',
  chart: { type: 'JaegerChart' },
  argocd: { syncWave: '-65' }
},

// Langfuse PostgreSQL
{
  name: 'langfuse-postgres',
  namespace: 'observability',
  chart: { type: 'LangfusePostgresChart' },
  argocd: { syncWave: '-65' }
},

// Langfuse
{
  name: 'langfuse',
  namespace: 'observability',
  chart: { type: 'LangfuseChart' },
  argocd: { syncWave: '-60' }
},

// Dapr tracing configuration
{
  name: 'dapr-tracing-config',
  namespace: 'dapr-agents',
  chart: { type: 'DaprTracingConfigChart' },
  argocd: { syncWave: '-55' }
},
```

---

#### 3.2 Register Charts

**File:** `cdk8s/lib/idpbuilder-chart-factory.ts`

**Additions:**
```typescript
import { ObservabilityNamespaceChart } from '../charts/infra/observability-namespace-chart';
import { JaegerChart } from '../charts/infra/jaeger-chart';
import { LangfusePostgresChart } from '../charts/infra/langfuse-postgres-chart';
import { LangfuseChart } from '../charts/infra/langfuse-chart';
import { ObservabilitySecretsChart } from '../charts/secrets/observability-secrets-chart';
import { DaprTracingConfigChart } from '../charts/infra/dapr-tracing-config-chart';

IdpBuilderChartFactory.register('ObservabilityNamespaceChart', ObservabilityNamespaceChart);
IdpBuilderChartFactory.register('JaegerChart', JaegerChart);
IdpBuilderChartFactory.register('LangfusePostgresChart', LangfusePostgresChart);
IdpBuilderChartFactory.register('LangfuseChart', LangfuseChart);
IdpBuilderChartFactory.register('ObservabilitySecretsChart', ObservabilitySecretsChart);
IdpBuilderChartFactory.register('DaprTracingConfigChart', DaprTracingConfigChart);
```

---

#### 3.3 Azure Key Vault Secrets

**Required secrets to add:**
| Secret Name | Description |
|-------------|-------------|
| LANGFUSE-POSTGRES-USER | PostgreSQL username (e.g., `langfuse`) |
| LANGFUSE-POSTGRES-PASSWORD | PostgreSQL password |
| LANGFUSE-NEXTAUTH-SECRET | NextAuth.js secret (base64, 32 bytes) |
| LANGFUSE-SALT | Langfuse salt (base64, 32 bytes) |
| LANGFUSE-ENCRYPTION-KEY | Encryption key (hex, 64 chars) |
| LANGFUSE-PUBLIC-KEY | API public key for SDK |
| LANGFUSE-SECRET-KEY | API secret key for SDK |

---

## Deployment Order

| Order | Component | Sync Wave | Dependencies |
|-------|-----------|-----------|--------------|
| 1 | observability-secrets | -75 | Azure Key Vault |
| 2 | observability-namespace | -70 | None |
| 3 | jaeger | -65 | namespace |
| 4 | langfuse-postgres | -65 | namespace, secrets |
| 5 | langfuse | -60 | postgres, secrets |
| 6 | dapr-tracing-config | -55 | jaeger |
| 7 | speckit-agents (updated) | -60 | tracing-config, langfuse |

---

## Verification Steps

### 1. Jaeger Verification

```bash
# Check deployment
kubectl get pods -n observability -l app=jaeger

# Port-forward to UI
kubectl port-forward -n observability svc/jaeger-query 16686:16686

# Open http://localhost:16686
# Verify services appear after agent activity
```

### 2. Langfuse Verification

```bash
# Check deployment
kubectl get pods -n observability -l app=langfuse

# Port-forward to UI
kubectl port-forward -n observability svc/langfuse 3000:3000

# Open http://localhost:3000
# Create initial admin user
# Verify traces appear after agent activity
```

### 3. Tracing Verification

```bash
# Submit a workflow
kubectl run curl-test --rm -i --restart=Never --image=curlimages/curl -- \
  curl -X POST http://speckit-orchestrator.dapr-agents.svc.cluster.local:8000/run \
  -H "Content-Type: application/json" \
  -d '{"task": "Test observability"}'

# Check Jaeger for traces
# Check Langfuse for LLM generations
```

### 4. Remote Access Verification

```bash
# From Tailscale-connected device
curl -k https://jaeger.tail286401.ts.net/api/services
curl -k https://langfuse.tail286401.ts.net/api/health
```

---

## Rollback Plan

If issues occur:

1. **Remove tracing config:** Delete `dapr-tracing-config` app (agents continue without tracing)
2. **Remove Langfuse instrumentation:** Revert agent code changes
3. **Remove infrastructure:** Delete observability namespace apps
4. **Clean up secrets:** Remove Azure Key Vault entries

All changes are additive; existing functionality unaffected if rolled back.

---

## Success Criteria Verification

| Criterion | Verification Method |
|-----------|---------------------|
| Trace visibility (100%) | Submit 10 workflows, verify all spans in Jaeger |
| LLM capture rate (100%) | Compare Langfuse generation count to agent logs |
| Debug time (<5 min) | Time a debugging exercise using both UIs |
| Remote access (<3s) | Measure page load from Tailscale device |
| Data retention (7 days) | Query for week-old data after 7+ days |
| Uptime (99%) | Monitor over 1 week |

---

## Files to Create/Modify

### New Files (CDK8s)
- `cdk8s/charts/infra/observability-namespace-chart.ts`
- `cdk8s/charts/infra/jaeger-chart.ts`
- `cdk8s/charts/infra/langfuse-postgres-chart.ts`
- `cdk8s/charts/infra/langfuse-chart.ts`
- `cdk8s/charts/infra/dapr-tracing-config-chart.ts`
- `cdk8s/charts/secrets/observability-secrets-chart.ts`

### Modified Files (CDK8s)
- `cdk8s/config/applications.ts`
- `cdk8s/lib/idpbuilder-chart-factory.ts`
- `cdk8s/charts/platform/ingress-tailscale-publish-chart.ts`
- `cdk8s/charts/apps/speckit-agents-chart.ts`

### New Files (Agents)
- `speckit-agents/src/common/observability.py`

### Modified Files (Agents)
- `speckit-agents/requirements.txt`
- `speckit-agents/src/agents/base.py`
