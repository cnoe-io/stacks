# Quickstart: LGTM Observability Stack

**Feature**: 111-configure-k8s-observability
**Date**: 2025-12-19

## Overview

This guide covers deploying and verifying the LGTM observability stack (Loki, Grafana, Tempo, Mimir) plus Pyroscope on K3s.

---

## Prerequisites

### 1. Cluster Requirements

```bash
# Verify K3s is running
kubectl get nodes
# Expected: 1 node Ready

# Verify storage provisioner
kubectl get sc
# Expected: local-path (default)

# Check available resources
kubectl top nodes
# Expected: At least 4GB available memory
```

### 2. Tailscale Operator

```bash
# Verify Tailscale operator is running
kubectl get pods -n tailscale -l app=tailscale-operator
# Expected: 1/1 Running

# Verify auth key secret exists
kubectl get secret -n tailscale tailscale-auth-key
# Expected: secret found
```

### 3. ArgoCD

```bash
# Verify ArgoCD is healthy
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
# Expected: 1/1 Running
```

---

## Deployment

### Step 1: Synthesize CDK8s Charts

```bash
cd cdk8s
npm run synth
```

### Step 2: Verify Generated Manifests

```bash
# Check LGTM stack manifests were generated
ls -la dist/lgtm-*/

# Expected directories:
# dist/lgtm-mimir/
# dist/lgtm-loki/
# dist/lgtm-tempo/
# dist/lgtm-pyroscope/
# dist/lgtm-otel-collector/
# dist/lgtm-grafana/
```

### Step 3: Deploy via ArgoCD

```bash
# Sync all applications
argocd app sync argocd/observability-namespace --insecure
argocd app sync argocd/lgtm-mimir --insecure
argocd app sync argocd/lgtm-loki --insecure
argocd app sync argocd/lgtm-tempo --insecure
argocd app sync argocd/lgtm-pyroscope --insecure
argocd app sync argocd/lgtm-otel-collector --insecure
argocd app sync argocd/lgtm-grafana --insecure

# Or sync all at once
argocd app sync -l app.kubernetes.io/part-of=lgtm-stack --insecure
```

### Step 4: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n observability -l app.kubernetes.io/part-of=lgtm-stack

# Expected output:
# NAME                              READY   STATUS    RESTARTS   AGE
# mimir-xxx                         1/1     Running   0          2m
# loki-xxx                          1/1     Running   0          2m
# tempo-xxx                         1/1     Running   0          2m
# pyroscope-xxx                     1/1     Running   0          2m
# otel-collector-xxx                1/1     Running   0          2m
# grafana-xxx                       1/1     Running   0          2m
```

### Step 5: Verify PVCs

```bash
kubectl get pvc -n observability

# Expected output:
# NAME            STATUS   VOLUME    CAPACITY   ACCESS MODES
# mimir-data      Bound    pvc-xxx   20Gi       RWO
# loki-data       Bound    pvc-xxx   20Gi       RWO
# tempo-data      Bound    pvc-xxx   20Gi       RWO
# pyroscope-data  Bound    pvc-xxx   10Gi       RWO
```

---

## Verification

### 1. Test OTEL Collector

```bash
# Port-forward to OTEL Collector
kubectl port-forward -n observability svc/otel-collector 4318:4318 &

# Send test trace using curl
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{"key": "service.name", "value": {"stringValue": "test-service"}}]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "5B8EFFF798038103D269B633813FC60C",
          "spanId": "EEE19B7EC3C1B174",
          "name": "test-span",
          "kind": 1,
          "startTimeUnixNano": "1544712660000000000",
          "endTimeUnixNano": "1544712661000000000"
        }]
      }]
    }]
  }'

# Expected: HTTP 200 OK
```

### 2. Test Mimir (Metrics)

```bash
# Port-forward to Mimir
kubectl port-forward -n observability svc/mimir 9009:9009 &

# Check Mimir health
curl http://localhost:9009/ready
# Expected: ready

# Query metrics (should return empty initially)
curl 'http://localhost:9009/prometheus/api/v1/query?query=up'
# Expected: {"status":"success","data":{"resultType":"vector","result":[]}}
```

### 3. Test Loki (Logs)

```bash
# Port-forward to Loki
kubectl port-forward -n observability svc/loki 3100:3100 &

# Check Loki health
curl http://localhost:3100/ready
# Expected: ready

# Query labels (should return basic labels)
curl http://localhost:3100/loki/api/v1/labels
# Expected: {"status":"success","data":["__name__"]}
```

### 4. Test Tempo (Traces)

```bash
# Port-forward to Tempo
kubectl port-forward -n observability svc/tempo 3200:3200 &

# Check Tempo health
curl http://localhost:3200/ready
# Expected: ready

# Search for traces (empty initially)
curl 'http://localhost:3200/api/search?q={}'
# Expected: {"traces":[]}
```

### 5. Test Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/grafana 3000:3000 &

# Open browser
open http://localhost:3000

# Default credentials: admin / admin
# Check datasources: Configuration > Data sources
# Expected: Mimir, Loki, Tempo, Pyroscope all configured
```

---

## Tailscale Access

### Service URLs

Once Tailscale serve pods are running, access via:

| Service | URL |
|---------|-----|
| OTEL Collector | `https://otel-collector.tail286401.ts.net:4318` |
| Grafana | `https://grafana.tail286401.ts.net` |
| Mimir | `https://mimir.tail286401.ts.net:9009` |

### Verify Tailscale Services

```bash
# Check Tailscale serve pods
kubectl get pods -n tailscale -l app.kubernetes.io/component=tailscale-serve

# Check pod logs for service registration
kubectl logs -n tailscale -l app.kubernetes.io/name=otel-collector-tailscale-serve --tail=20
# Expected: "Service running at https://svc-otel-collector..."
```

---

## Send Test Data

### Using otel-cli (Traces)

```bash
# Install otel-cli
go install github.com/equinix-labs/otel-cli@latest

# Send trace to collector
otel-cli span \
  --endpoint http://localhost:4318 \
  --service test-service \
  --name "test-operation" \
  --attrs "host=thinkpad,env=test"
```

### Using promtool (Metrics)

```bash
# Create test metrics file
cat > /tmp/metrics.txt << 'EOF'
# HELP test_counter A test counter
# TYPE test_counter counter
test_counter{host="thinkpad"} 42
EOF

# Send to Mimir via remote write (requires promtool)
# Or use curl with OTLP metrics format
```

### Using logcli (Logs)

```bash
# Install logcli
go install github.com/grafana/loki/cmd/logcli@latest

# Query logs
logcli --addr=http://localhost:3100 query '{job="test"}'
```

---

## Troubleshooting

### OTEL Collector Not Receiving Data

```bash
# Check collector logs
kubectl logs -n observability -l app.kubernetes.io/name=otel-collector --tail=50

# Check internal metrics
kubectl port-forward -n observability svc/otel-collector 8888:8888 &
curl http://localhost:8888/metrics | grep otelcol_receiver
```

### Mimir/Loki/Tempo Not Storing Data

```bash
# Check component health
kubectl exec -n observability deploy/mimir -- wget -qO- http://localhost:9009/ready
kubectl exec -n observability deploy/loki -- wget -qO- http://localhost:3100/ready
kubectl exec -n observability deploy/tempo -- wget -qO- http://localhost:3200/ready

# Check PVC usage
kubectl exec -n observability deploy/mimir -- df -h /data
kubectl exec -n observability deploy/loki -- df -h /data/loki
kubectl exec -n observability deploy/tempo -- df -h /data/tempo
```

### Grafana Datasources Not Working

```bash
# Check datasource configuration
kubectl get configmap -n observability grafana-datasources -o yaml

# Test datasource connectivity from Grafana pod
kubectl exec -n observability deploy/grafana -- curl -s http://mimir:9009/ready
kubectl exec -n observability deploy/grafana -- curl -s http://loki:3100/ready
kubectl exec -n observability deploy/grafana -- curl -s http://tempo:3200/ready
```

### Tailscale Service Not Accessible

```bash
# Check Tailscale pod status
kubectl get pods -n tailscale -l app.kubernetes.io/component=tailscale-serve

# Check auth key
kubectl get secret -n tailscale tailscale-auth-key -o jsonpath='{.data.auth-key}' | base64 -d | head -c 20
# Expected: starts with "tskey-auth-"

# Check ACLs in Tailscale Admin Console
# Ensure tag:k8s-services is auto-approved for svc:grafana, svc:otel-collector, etc.
```

---

## Cleanup (Legacy Removal)

After verifying the LGTM stack is working:

```bash
# Remove legacy otel-stack ArgoCD application
argocd app delete argocd/otel-stack --insecure

# Verify ClickHouse resources are gone
kubectl get pods -n observability -l app.kubernetes.io/name=clickhouse
# Expected: No resources found

# Verify ClickHouse PVC is gone
kubectl get pvc -n observability -l app.kubernetes.io/name=clickhouse
# Expected: No resources found
```

**Note**: Langfuse's ClickHouse (`langfuse-clickhouse`) should remain intact.

---

## Success Criteria Verification

| Criterion | Command | Expected |
|-----------|---------|----------|
| SC-001: Metrics in 30s | Send metric, query in Grafana | Visible within 30s |
| SC-002: Traces in 5s | Send trace, search in Tempo | Searchable within 5s |
| SC-003: Logs in 30s | Send log, query in Loki | Queryable within 30s |
| SC-004: Tailscale access | curl grafana.tail286401.ts.net | HTTP 200 |
| SC-005: 30-day retention | Check component configs | retention_period: 720h |
| SC-006: Multi-workstation | Send from 5+ hosts | All data visible |
| SC-007: Unified dashboards | Open Grafana | All datasources work |
| SC-008: Persistent storage | Restart pods, check data | Data preserved |
| SC-009: Legacy removed | Check for ClickHouse | Not found (except langfuse-clickhouse) |
| SC-010: Langfuse works | Access langfuse.tail286401.ts.net | HTTP 200 |
