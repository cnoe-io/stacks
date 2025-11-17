# kgateway Helm Values Research Summary

## Research Completed

Successfully researched and documented the kgateway Helm chart values structure for enabling agentgateway and AI extension with OpenTelemetry integration.

## Key Findings

### 1. Exact Helm Values Structure

**For agentgateway:**
```yaml
agentGateway:
  enabled: true
  enableAlphaAPIs: false  # Optional: for alpha features
```

**For AI Extension:**
```yaml
gateway:
  aiExtension:
    enabled: true
```

### 2. Minimal Helm Installation Command

```bash
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --set agentGateway.enabled=true \
  --set gateway.aiExtension.enabled=true \
  --version v2.1.1
```

### 3. OpenTelemetry Integration

OpenTelemetry tracing is NOT configured via Helm chart values directly. Instead, it's configured through:

1. **GatewayParameters** CRD with spec.kube.aiExtension.tracing section
2. **HTTPListenerPolicy** CRD for gateway-level tracing

**GatewayParameters Tracing Configuration:**
```yaml
spec:
  kube:
    aiExtension:
      tracing:
        enabled: true
        endpoint: "http://opentelemetry-collector.telemetry.svc.cluster.local:4317"
        sampler:
          type: "traceidratio"
          arg: "1.0"  # 100% sampling
        protocol: "grpc"
        transportSecurity: "plaintext"
        timeout: 10000
```

### 4. kgateway-crds Chart

The kgateway-crds chart has minimal configurable values:

```bash
# Installation
helm upgrade -i --create-namespace --namespace kgateway-system \
  --version v2.1.1 \
  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds

# No special values needed - primarily installs CRDs
```

### 5. Important Breaking Changes

In recent versions, GatewayParameters field changed:

**Old (deprecated):**
```yaml
spec:
  kube:
    agentGateway:  # PascalCase
      enabled: true
```

**New (current):**
```yaml
spec:
  kube:
    agentgateway:  # lowercase
      enabled: true
```

### 6. AI Gateway Deprecation Notice

AI Gateway for Envoy-based proxies is deprecated and will be removed in kgateway v2.2. Use **agentgateway** instead for ongoing AI capabilities.

## Deliverables

Three comprehensive documents have been created:

### 1. kgateway_helm_values_reference.md (12 KB, 520 lines)
Complete reference documentation including:
- Core Helm values for agentgateway and AI extension
- Complete values.yaml example
- GatewayParameters configuration examples
- HTTPListenerPolicy for tracing
- kgateway-crds chart details
- Full installation checklist
- OpenTelemetry integration notes
- Breaking changes and important notes
- References to official documentation

### 2. kgateway_helm_values_quickstart.yaml (7.2 KB, 263 lines)
Ready-to-use YAML file with:
- Helm chart values section (extracted for direct use)
- GatewayParameters CRD for agentgateway
- GatewayParameters CRD for AI extension with OpenTelemetry
- Gateway resource (Kubernetes Gateway API)
- HTTPListenerPolicy for tracing
- Complete installation instructions

### 3. KGATEWAY_HELM_RESEARCH_SUMMARY.md (this file)
Quick reference guide with all key findings

## Usage Instructions

### Option 1: Using Helm CLI with --set flags
```bash
# Install prerequisites
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

helm upgrade -i --create-namespace --namespace kgateway-system \
  --version v2.1.1 \
  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds

# Install with --set flags
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --set agentGateway.enabled=true \
  --set gateway.aiExtension.enabled=true \
  --version v2.1.1
```

### Option 2: Using values file
```bash
# Extract Helm values section from quickstart.yaml
# Save as kgateway-values.yaml
# Then:
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  -f kgateway-values.yaml \
  --version v2.1.1

# Deploy CRDs
kubectl apply -f kgateway_helm_values_quickstart.yaml
```

## Supported Sampler Types for OpenTelemetry

| Type | Description | Sampling Rate |
|------|-------------|---------------|
| `alwaysOn` | Sample 100% | 100% |
| `alwaysOff` | Sample 0% | 0% |
| `traceidratio` | Based on trace ID | Configurable via `arg` |
| `parentbased_alwaysOn` | Inherit from parent | Parent 100% |
| `parentbased_traceidratio` | Inherit or fallback | Parent or `arg` |

## OTLP Protocol Support

kgateway supports both:

1. **gRPC** (recommended, default)
   - Port: 4317
   - Protocol field: `grpc`

2. **HTTP**
   - Port: 4318
   - Protocol field: `http`

## Next Steps for Integration

1. Read `kgateway_helm_values_reference.md` for complete detailed documentation
2. Use `kgateway_helm_values_quickstart.yaml` as a template for your deployment
3. Customize namespaces, image versions, and resource limits as needed
4. Deploy and verify with provided kubectl commands
5. Access agentgateway and AI extension via created services

## File Locations

All documents are located in the repository root:

- `/kgateway_helm_values_reference.md` - Full reference documentation
- `/kgateway_helm_values_quickstart.yaml` - Ready-to-use YAML templates
- `/KGATEWAY_HELM_RESEARCH_SUMMARY.md` - This summary file

## References

- Official kgateway documentation: https://kgateway.dev/docs/
- Helm charts registry: https://cr.kgateway.dev/kgateway-dev/charts/
- GitHub repository: https://github.com/kgateway-dev/kgateway
- Kubernetes Gateway API: https://gateway-api.sigs.k8s.io/
- OpenTelemetry: https://opentelemetry.io/

## Research Methodology

Research was conducted through:
1. Official kgateway documentation website
2. GitHub repository exploration
3. Helm chart value references
4. OpenTelemetry integration guides
5. Official CNCF and LFX Mentorship blog posts
6. API reference documentation

All information is current as of November 2025 (kgateway v2.1.1 and v2.1.0-main).

