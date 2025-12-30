# CAIPE Observability Testing Guide

This guide explains how to test and validate the CAIPE observability configuration.

## Overview

CAIPE uses a dual-observability architecture:
- **Langfuse**: LLM-specific tracing (token usage, costs, conversation flows)
- **LGTM Stack**: Infrastructure observability (metrics, logs, traces, profiles)

## Prerequisites

1. CAIPE deployed in `ai-platform-engineering` namespace
2. Langfuse deployed in `observability` namespace
3. OTEL Collector deployed in `observability` namespace
4. Azure Key Vault secrets synced (Langfuse API keys)

## Automated Validation

Run the validation script:

```bash
./scripts/test-caipe-observability.sh
```

This script checks:
1. Namespace exists
2. Langfuse credentials secret synced
3. ENABLE_TRACING=true in all CAIPE pods
4. OTEL collector connectivity
5. Langfuse service availability
6. ServiceMonitors (if Prometheus Operator installed)
7. Supervisor agent deployment health

## Manual Testing

### 1. Verify Environment Variables

Check that observability env vars are set in each pod:

```bash
# Supervisor agent
kubectl exec -n ai-platform-engineering deploy/supervisor-agent -- env | grep -E "(ENABLE_TRACING|OTEL_|LANGFUSE_)"

# Expected output:
# ENABLE_TRACING=true
# OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4317
# OTEL_SERVICE_NAME=caipe-supervisor-agent
# LANGFUSE_ENABLED=true
# LANGFUSE_HOST=http://langfuse.observability.svc.cluster.local:3000
# LANGFUSE_PUBLIC_KEY=pk-lf-...
# LANGFUSE_SECRET_KEY=sk-lf-...
```

### 2. Generate Test Traces

Trigger a conversation with the supervisor agent to generate traces:

```bash
# Port-forward to supervisor agent
kubectl port-forward -n ai-platform-engineering svc/supervisor-agent 8000:8000 &

# Send a test request
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What ArgoCD applications are deployed?"}'
```

### 3. View Traces in Langfuse

Access Langfuse UI:

```bash
# Via Tailscale (recommended)
open https://langfuse-<cluster>.tail286401.ts.net

# Via local ingress
open https://langfuse.cnoe.localtest.me:8443
```

Navigate to **Traces** and look for:
- Service name: `caipe-supervisor-agent`, `caipe-agent-argocd`, etc.
- Token usage metrics
- Latency measurements
- Tool call spans

### 4. View Traces in Grafana/Tempo

Access Grafana:

```bash
# Via Tailscale
open https://grafana-<cluster>.tail286401.ts.net

# Via local ingress
open https://grafana.cnoe.localtest.me:8443
```

Navigate to **Explore** > **Tempo** and search for:
- Service: `caipe-*`
- TraceQL: `{resource.service.name =~ "caipe-.*"}`

### 5. Check Prometheus Metrics

If Prometheus is installed, verify metrics scraping:

```bash
# Check ServiceMonitor status
kubectl get servicemonitor -n ai-platform-engineering

# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &

# Query CAIPE metrics
curl 'http://localhost:9090/api/v1/query?query=up{namespace="ai-platform-engineering"}'
```

## Troubleshooting

### Traces Not Appearing in Langfuse

1. **Check credentials secret**:
   ```bash
   kubectl get secret caipe-langfuse-credentials -n ai-platform-engineering -o yaml
   ```

2. **Verify ExternalSecret sync**:
   ```bash
   kubectl get externalsecret -n ai-platform-engineering -o wide
   ```

3. **Check agent logs**:
   ```bash
   kubectl logs -n ai-platform-engineering deploy/supervisor-agent --tail=50 | grep -i langfuse
   ```

### OTEL Collector Not Receiving Data

1. **Check OTEL collector logs**:
   ```bash
   kubectl logs -n observability deploy/otel-collector --tail=50
   ```

2. **Verify endpoint connectivity**:
   ```bash
   kubectl exec -n ai-platform-engineering deploy/supervisor-agent -- \
     nc -zv otel-collector.observability.svc.cluster.local 4317
   ```

### ENABLE_TRACING Not Set

1. **Resync ArgoCD application**:
   ```bash
   argocd app sync argocd/caipe-supervisor --insecure
   ```

2. **Check deployment manifest**:
   ```bash
   kubectl get deploy supervisor-agent -n ai-platform-engineering -o yaml | grep -A5 ENABLE_TRACING
   ```

## Architecture Reference

```
┌─────────────────────────────────────────────────────────────────────┐
│                   CAIPE Agents (ai-platform-engineering)            │
│                                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ Supervisor  │  │   ArgoCD    │  │   GitHub    │  ...            │
│  │   Agent     │  │   Agent     │  │   Agent     │                 │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │
│         │                │                │                        │
│         │  ENABLE_TRACING=true                                     │
│         │  OTEL_EXPORTER_OTLP_ENDPOINT                             │
│         │  LANGFUSE_HOST, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY │
│         │                │                │                        │
└─────────┼────────────────┼────────────────┼────────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Observability Namespace                            │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                   OTEL Collector (:4317)                      │ │
│  │     Routes: traces → Tempo, metrics → Mimir, logs → Loki     │ │
│  └──────────────────────────┬────────────────────────────────────┘ │
│                             │                                      │
│         ┌───────────────────┼───────────────────┐                  │
│         ▼                   ▼                   ▼                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐            │
│  │    Tempo    │    │    Mimir    │    │    Loki     │            │
│  │  (Traces)   │    │  (Metrics)  │    │   (Logs)    │            │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘            │
│         │                  │                  │                    │
│         └──────────────────┼──────────────────┘                    │
│                            ▼                                       │
│                    ┌─────────────┐                                 │
│                    │   Grafana   │                                 │
│                    │ (Dashboards)│                                 │
│                    └─────────────┘                                 │
│                                                                    │
│  ┌───────────────────────────────────────────────────────────────┐│
│  │                     Langfuse (:3000)                          ││
│  │         LLM-specific: token usage, costs, latency             ││
│  └───────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────────┘
```

## Success Criteria Checklist

- [ ] All CAIPE agents have `ENABLE_TRACING=true`
- [ ] Langfuse credentials secret exists and is synced
- [ ] Traces visible in Langfuse UI
- [ ] Traces visible in Grafana/Tempo
- [ ] OTEL collector receiving data from CAIPE agents
- [ ] ServiceMonitors scraping metrics (if Prometheus installed)
- [ ] Test script passes all validation checks
