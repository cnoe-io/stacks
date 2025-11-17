# kgateway Helm Chart Values Research

## Summary

This document provides complete Helm values structure for enabling agentgateway and AI extension in kgateway, including OpenTelemetry integration configuration.

---

## 1. Core Helm Values for agentgateway and AI Extension

### 1.1 Basic Configuration (values.yaml)

```yaml
# Enable agentgateway integration
agentGateway:
  enabled: true
  enableAlphaAPIs: false  # Set to true for alpha features (Waypoint, etc.)

# Enable AI Gateway extension
gateway:
  aiExtension:
    enabled: true
```

### 1.2 Installation Commands

```bash
# Install kgateway CRDs first
helm upgrade -i --create-namespace --namespace kgateway-system \
  --version v2.1.1 \
  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds

# Install kgateway with agentgateway and AI extension enabled
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --set agentGateway.enabled=true \
  --set gateway.aiExtension.enabled=true \
  --version v2.1.1

# With development build (latest main)
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --set agentGateway.enabled=true \
  --set agentGateway.enableAlphaAPIs=true \
  --set gateway.aiExtension.enabled=true \
  --set controller.image.pullPolicy=Always \
  --version v2.1.0-main
```

### 1.3 Verification

```bash
# Verify installation
helm get values kgateway -n kgateway-system -o yaml

# Expected output:
# agentGateway:
#   enabled: true
#   enableAlphaAPIs: false
# gateway:
#   aiExtension:
#     enabled: true
```

---

## 2. Complete kgateway Helm Values File Example

```yaml
# kgateway/values.yaml

# Controller configuration
controller:
  replicaCount: 1
  image:
    registry: cr.kgateway.dev
    repository: kgateway-dev/kgateway
    tag: "v2.1.1"
    pullPolicy: IfNotPresent
  
  # Service configuration
  service:
    type: ClusterIP
    ports:
      grpc: 9977
      health: 9093
      metrics: 9092
  
  # Resource configuration
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  
  # Extra environment variables
  extraEnv: {}
  logLevel: "info"

# agentgateway integration
agentGateway:
  enabled: true
  enableAlphaAPIs: false  # Enable for Waypoint and other alpha features

# Gateway AI extension
gateway:
  aiExtension:
    enabled: true

# Create namespace
createNamespace: true

# Namespace name
namespace: kgateway-system

# RBAC configuration
rbac:
  create: true

# Service account
serviceAccount:
  create: true
  name: kgateway
```

---

## 3. GatewayParameters Configuration (CRD)

The actual AI extension and agentgateway behavior is configured through the `GatewayParameters` Kubernetes custom resource:

### 3.1 Basic GatewayParameters for agentgateway

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: agentgateway-params
  namespace: kgateway-system
  labels:
    app: agentgateway
spec:
  kube:
    # agentgateway specific configuration
    agentgateway:
      enabled: true
      # Additional agentgateway-specific settings here
    
    # Service configuration
    service:
      type: LoadBalancer  # Use NodePort for local development
```

### 3.2 GatewayParameters with AI Extension

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: ai-gateway-params
  namespace: kgateway-system
  labels:
    app: kgateway-ai
spec:
  kube:
    aiExtension:
      enabled: true
      
      # Container port configuration
      ports:
        - name: ai-monitoring
          containerPort: 9092
      
      # Image configuration
      image:
        registry: cr.kgateway.dev
        repository: kgateway-dev/kgateway-ai-extension
        tag: "v2.1.1"
        pullPolicy: IfNotPresent
      
      # Resource limits
      resources:
        requests:
          memory: "256Mi"
          cpu: "250m"
        limits:
          memory: "1Gi"
          cpu: "1000m"
      
      # Environment variables
      env:
        - name: LOG_LEVEL
          value: "info"
    
    # Service configuration
    service:
      type: LoadBalancer  # Use NodePort for local testing
      ports:
        - port: 80
          targetPort: 8080
          protocol: TCP
```

### 3.3 GatewayParameters with OpenTelemetry Tracing

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: ai-gateway-with-tracing
  namespace: kgateway-system
  labels:
    app: kgateway-ai-traces
spec:
  kube:
    aiExtension:
      enabled: true
      
      # OpenTelemetry tracing configuration
      tracing:
        enabled: true
        
        # OTLP collector endpoint (gRPC)
        endpoint: "http://opentelemetry-collector.telemetry.svc.cluster.local:4317"
        
        # Sampler configuration
        sampler:
          type: "traceidratio"  # or "alwaysOn", "parentbased_traceidratio"
          arg: "1.0"            # 1.0 = 100% sampling, 0.1 = 10% sampling
        
        # Timeout in milliseconds
        timeout: 10000
        
        # Protocol: "grpc" or "http"
        protocol: "grpc"
        
        # Transport security
        transportSecurity: "tls"  # or "plaintext"
      
      # Container ports
      ports:
        - name: ai-monitoring
          containerPort: 9092
      
      # Image configuration
      image:
        registry: cr.kgateway.dev
        repository: kgateway-dev/kgateway-ai-extension
        tag: "v2.1.1"
      
      # Environment variables for OpenTelemetry
      env:
        - name: LOG_LEVEL
          value: "debug"
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: "grpc"
        - name: OTEL_SDK_DISABLED
          value: "false"
    
    # Service configuration
    service:
      type: LoadBalancer
```

---

## 4. HTTPListenerPolicy for OpenTelemetry Tracing

Configure gateway-level tracing through HTTPListenerPolicy:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: HTTPListenerPolicy
metadata:
  name: otel-listener-policy
  namespace: kgateway-system
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: agentgateway
  tracing:
    enabled: true
    
    # OpenTelemetry backend configuration
    providers:
      - name: opentelemetry
        
        # Trace sampling configuration
        sampling:
          overall: "100"  # 100% sampling (1-100)
          
        # OpenTelemetry collector details
        endpoint:
          type: GRPC
          host: "opentelemetry-collector.telemetry.svc.cluster.local"
          port: 4317
          tls:
            enabled: false
        
        # Custom trace attributes
        customTags:
          - name: "service.version"
            literal:
              value: "v2.1.1"
          - name: "environment"
            literal:
              value: "kubernetes"
```

---

## 5. kgateway-crds Helm Chart

### 5.1 Chart Details

The kgateway-crds chart deploys Custom Resource Definitions required by kgateway.

```bash
# Installation
helm upgrade -i --create-namespace --namespace kgateway-system \
  --version v2.1.1 \
  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds
```

### 5.2 kgateway-crds values.yaml

The kgateway-crds chart has minimal configurable values (primarily defines CRDs):

```yaml
# kgateway-crds/values.yaml

# Namespace where CRDs will be installed
namespace: kgateway-system

# CRD configuration
crds:
  # Install Gateway API CRDs
  gatewayAPI: true
  
  # Install kgateway custom resources
  kgateway: true
```

### 5.3 Required Gateway API CRDs (Upstream)

Before installing kgateway-crds, install Gateway API standard CRDs:

```bash
# Install Kubernetes Gateway API CRDs (v1.4.0 recommended)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# Verify installation
kubectl get crd | grep gateway
# Expected: gatewayclasses.gateway.networking.k8s.io, gateways.gateway.networking.k8s.io, etc.
```

---

## 6. Complete Installation Checklist

### Step 1: Install Gateway API CRDs
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

### Step 2: Install kgateway CRDs
```bash
helm upgrade -i --create-namespace --namespace kgateway-system \
  --version v2.1.1 \
  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds
```

### Step 3: Install kgateway with agentgateway and AI Extension
```bash
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --set agentGateway.enabled=true \
  --set gateway.aiExtension.enabled=true \
  --version v2.1.1
```

### Step 4: Deploy GatewayParameters (if using custom config)
```bash
kubectl apply -f gateway-parameters.yaml
```

### Step 5: Create Gateway Resource
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agentgateway
  namespace: kgateway-system
spec:
  gatewayClassName: agentgateway
  listeners:
  - protocol: HTTP
    port: 8080
    name: http
    allowedRoutes:
      namespaces:
        from: All
```

### Step 6: Verify Installation
```bash
# Check Helm values
helm get values kgateway -n kgateway-system -o yaml

# Check pods
kubectl get pods -n kgateway-system

# Check Gateway
kubectl get gateway -n kgateway-system

# Check services
kubectl get svc -n kgateway-system
```

---

## 7. OpenTelemetry Integration Notes

### 7.1 Sampler Types

Supported OpenTelemetry sampler types in kgateway:

| Type | Description | Usage |
|------|-------------|-------|
| `alwaysOn` | Sample all traces | Development/testing |
| `alwaysOff` | Sample no traces | Production (no tracing) |
| `traceidratio` | Sample % based on trace ID | `arg: "0.1"` for 10% |
| `parentbased_alwaysOn` | Sample if parent is sampled | Child span inherits parent sampling |
| `parentbased_traceidratio` | Parent-based with fallback | Best for distributed systems |

### 7.2 OTLP Protocols

kgateway supports both gRPC and HTTP OTLP:

```yaml
# gRPC (default, recommended)
tracing:
  protocol: "grpc"
  endpoint: "http://otel-collector.telemetry.svc.cluster.local:4317"

# HTTP
tracing:
  protocol: "http"
  endpoint: "http://otel-collector.telemetry.svc.cluster.local:4318"
```

### 7.3 GenAI Semantic Conventions

kgateway AI Gateway follows OpenTelemetry GenAI semantic conventions for tracing:

- Supports tracing for: OpenAI, Anthropic, Gemini, and other LLM providers
- Spans track: LLM requests, token usage, latency, errors
- Exporters: Any OTLP-compatible backend (Jaeger, Tempo, Datadog, etc.)

---

## 8. Important Notes and Breaking Changes

### 8.1 Field Naming Changes

In recent versions of kgateway, there was a breaking change to GatewayParameters:

**Old (deprecated):**
```yaml
spec:
  kube:
    agentGateway:
      enabled: true
```

**New (current):**
```yaml
spec:
  kube:
    agentgateway:  # lowercase 'gateway'
      enabled: true
```

### 8.2 AI Gateway Deprecation Notice

**Important**: AI Gateway for Envoy-based gateway proxies is deprecated and will be removed in kgateway v2.2. 

For ongoing AI capabilities, use **agentgateway** instead (fully supported, actively developed).

### 8.3 Alpha Features

Alpha features (like Waypoint) are disabled by default. Enable with:

```bash
--set agentGateway.enableAlphaAPIs=true
```

### 8.4 Image Pull Policy for Development

When using development builds (v2.1.0-main), use `IfNotPresent` or `Always`:

```bash
--set controller.image.pullPolicy=Always
```

---

## 9. References

- **Official Documentation**: https://kgateway.dev/docs/
- **Helm Charts Registry**: https://cr.kgateway.dev/kgateway-dev/charts/
- **GitHub Repository**: https://github.com/kgateway-dev/kgateway
- **AgentGateway Setup**: https://kgateway.dev/docs/main/agentgateway/setup/
- **AI Gateway Setup**: https://kgateway.dev/docs/main/ai/setup/
- **OpenTelemetry Integration**: https://kgateway.dev/docs/main/agentgateway/llm/tracing/
- **Kubernetes Gateway API**: https://gateway-api.sigs.k8s.io/

