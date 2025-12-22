# Research: SpecKit Agent Observability

**Feature ID:** 100-dapr-agent-speckit-observability
**Date:** 2025-12-03

---

## 1. Jaeger All-in-One Deployment

### Decision
Use **Jaeger v2.12.0** all-in-one image with Badger embedded storage.

### Rationale
- Jaeger v2 is built on OpenTelemetry Collector framework (future-proof)
- Badger storage provides persistence without requiring external databases
- All-in-one deployment suitable for development/single-node environments
- Native Zipkin-compatible collector endpoint works with Dapr out of the box

### Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Jaeger v2 all-in-one (Badger) | Simple, persistent, no external deps | Single-node only | **Selected** |
| Jaeger v1.75 (memory) | Stable, widely used | EOL Dec 2025, no persistence | Rejected |
| Jaeger v2 (Elasticsearch) | Scalable, production-ready | Complex setup, resource heavy | Out of scope |
| Tempo (Grafana) | Efficient, integrates with Grafana | Requires Grafana stack | Out of scope |

### Configuration Details

```yaml
# Image
image: jaegertracing/all-in-one:2.12.0

# Environment Variables
SPAN_STORAGE_TYPE: badger
BADGER_EPHEMERAL: false
BADGER_DIRECTORY_KEY: /badger/key
BADGER_DIRECTORY_VALUE: /badger/value
BADGER_SPAN_STORAGE_TTL: 168h  # 7 days
BADGER_DEPENDENCY_STORAGE_TTL: 168h

# Ports
- 16686: UI/Query (HTTP)
- 9411: Zipkin collector (Dapr sends here)
- 14268: OTLP HTTP
- 14250: OTLP gRPC

# Resources (development)
requests: cpu=200m, memory=512Mi
limits: cpu=500m, memory=1Gi

# Storage
PVC: 10Gi for /badger
```

---

## 2. Langfuse Self-Hosted Deployment

### Decision
Deploy **Langfuse v3.123.1** with dedicated PostgreSQL instance.

### Rationale
- Open-source self-hosted version avoids cloud dependency
- v3 is GA and built on OpenTelemetry (future integration potential)
- PostgreSQL is well-supported and can use existing patterns
- Self-hosted allows full control over data retention

### Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Langfuse self-hosted v3 | Full control, open source, OTel-based | Requires PostgreSQL | **Selected** |
| Langfuse Cloud | Managed, no ops burden | Data leaves cluster, cost | Rejected |
| LangSmith | LangChain native | Proprietary, cloud only | Rejected |
| Phoenix (Arize) | Open source, notebook integration | Less mature UI | Future consideration |

### Configuration Details

```yaml
# Image
image: langfuse/langfuse:3.123.1

# Required Environment Variables
DATABASE_URL: postgresql://langfuse:${password}@langfuse-postgres:5432/langfuse
NEXTAUTH_URL: https://langfuse-<cluster>.cnoe.localtest.me:8443
NEXTAUTH_SECRET: ${generated-secret}
SALT: ${generated-salt}
ENCRYPTION_KEY: ${generated-64-hex-chars}

# Ports
- 3000: Web UI and API

# Resources
requests: cpu=500m, memory=1Gi
limits: cpu=2000m, memory=3Gi

# PostgreSQL
image: postgres:16-alpine
PVC: 20Gi for /var/lib/postgresql/data
```

### Secret Generation

```bash
# NEXTAUTH_SECRET (base64, 32 bytes)
openssl rand -base64 32

# SALT (base64, 32 bytes)
openssl rand -base64 32

# ENCRYPTION_KEY (hex, 32 bytes = 64 hex chars)
openssl rand -hex 32
```

---

## 3. Dapr Tracing Configuration

### Decision
Configure Dapr to emit traces via Zipkin protocol to Jaeger collector.

### Rationale
- Dapr has native support for Zipkin protocol
- Jaeger all-in-one includes Zipkin-compatible collector on port 9411
- Zero-code instrumentation for service-to-service calls
- W3C trace context automatically propagated

### Configuration Details

```yaml
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: speckit-tracing
  namespace: dapr-agents
spec:
  tracing:
    samplingRate: "1"  # 100% for development
    zipkin:
      endpointAddress: "http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans"
```

### Agent Pod Annotation

```yaml
annotations:
  dapr.io/config: "speckit-tracing"
```

---

## 4. Langfuse Python SDK Integration

### Decision
Manually instrument SpecKit agents with Langfuse Python SDK using `@observe()` decorator.

### Rationale
- dapr-agents has no native Langfuse support (Issue #79 is open but not implemented)
- Langfuse Python SDK v3 is simple to integrate
- `@observe()` decorator provides automatic span creation
- Session management allows grouping by workflow instance ID

### Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Manual Langfuse SDK | Works now, full control | Requires code changes | **Selected** |
| Wait for Issue #79 | Native integration | Timeline unknown | Future migration |
| OpenLLMetry | Auto-instrumentation | Less LLM-specific | Rejected |
| Custom OTel spans | Standard protocol | No LLM-specific UI | Rejected |

### Implementation Pattern

```python
# requirements.txt addition
langfuse>=3.10.0

# Agent instrumentation
from langfuse import Langfuse
from langfuse.decorators import observe, langfuse_context

langfuse = Langfuse(
    public_key=os.environ["LANGFUSE_PUBLIC_KEY"],
    secret_key=os.environ["LANGFUSE_SECRET_KEY"],
    host=os.environ["LANGFUSE_HOST"]
)

@observe(name="specifier_process_task")
async def process_task(workflow_id: str, task: str):
    # Set session for grouping
    langfuse_context.update_current_observation(
        session_id=workflow_id,
        user_id="specifier"
    )

    # LLM call - automatically traced
    result = await llm.generate(...)
    return result
```

---

## 5. Tailscale Remote Access

### Decision
Follow existing `ingress-tailscale-publish-chart.ts` pattern to expose Jaeger and Langfuse.

### Rationale
- Consistent with other cluster services (argocd, kagent, etc.)
- LoadBalancer with `loadBalancerClass: tailscale` works automatically
- Let's Encrypt certificates provisioned by Tailscale
- No additional configuration required

### Configuration Details

```typescript
// Add to HOSTS array in ingress-tailscale-publish-chart.ts
{ name: 'jaeger', hostname: 'jaeger' },
{ name: 'langfuse', hostname: 'langfuse' },
```

---

## 6. Namespace and Sync Wave Strategy

### Decision
Deploy to new `observability` namespace with sync wave -70 (before agents).

### Rationale
- Isolated namespace for observability components
- Sync wave -70 ensures Jaeger is ready before agents start
- Agents can send traces immediately on startup
- Follows existing pattern (dapr-system=-120, dapr-agents=-60)

### Sync Wave Order

| Wave | Component |
|------|-----------|
| -120 | Dapr Runtime |
| -100 | Dapr Redis |
| -95 | Dapr Secrets |
| -90 | Dapr Components |
| **-70** | **Observability Namespace** |
| **-65** | **Jaeger + PostgreSQL** |
| **-60** | **Langfuse** |
| -60 | SpecKit Agents |

---

## 7. Storage Considerations

### Decision
Use local PersistentVolumes for both Jaeger and Langfuse PostgreSQL.

### Rationale
- Kind cluster uses local storage by default
- 10Gi sufficient for 7-day Jaeger trace retention
- 20Gi sufficient for Langfuse PostgreSQL with 7-day retention
- Production would use different storage class

### Retention Strategy

| Component | Retention | Mechanism |
|-----------|-----------|-----------|
| Jaeger | 7 days | Badger TTL (BADGER_SPAN_STORAGE_TTL) |
| Langfuse | 7 days | Application-level cleanup (LANGFUSE_RETENTION_DAYS) |

---

## References

- [Jaeger Downloads](https://www.jaegertracing.io/download/)
- [Jaeger Badger Storage](https://www.jaegertracing.io/docs/1.62/deployment/#badger---local-storage)
- [Langfuse Self-Hosting](https://langfuse.com/docs/deployment/self-host)
- [Langfuse Python SDK](https://langfuse.com/docs/sdk/python)
- [Dapr Tracing Setup](https://docs.dapr.io/operations/observability/tracing/setup-tracing/)
- [dapr-agents Issue #79](https://github.com/dapr/dapr-agents/issues/79)
