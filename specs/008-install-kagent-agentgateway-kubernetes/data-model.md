# Data Model: kagent and kgateway CRD Schemas

**Date**: November 17, 2025
**Feature**: 008-install-kagent-agentgateway-kubernetes

## Overview

This document defines the Custom Resource Definitions (CRDs) and their relationships for the kagent and kgateway deployment. These are Kubernetes-native resources managed by their respective controllers.

---

## Entity Relationship Diagram

```
┌─────────────────┐
│  Gateway API    │
│   (Kubernetes)  │
└────────┬────────┘
         │ references
         ▼
┌─────────────────┐     ┌─────────────────┐
│    Gateway      │     │  HTTPRoute      │
│  (kgateway)     │◄────┤  (kgateway)     │
└────────┬────────┘     └────────┬────────┘
         │                       │ routes to
         │ configures            ▼
         ▼              ┌─────────────────┐
┌─────────────────┐     │    Backend      │
│ GatewayParameters│    │  (MCP Server)   │
└─────────────────┘     └────────▲────────┘
                                 │
                                 │ deploys
                        ┌────────┴────────┐
                        │   MCPServer     │
                        │   (kagent)      │
                        └────────▲────────┘
                                 │ uses
                        ┌────────┴────────┐
                        │     Agent       │
                        │   (kagent)      │
                        └────────┬────────┘
                                 │ references
                        ┌────────▼────────┐
                        │  ModelConfig    │
                        │   (kagent)      │
                        └────────┬────────┘
                                 │ uses
                        ┌────────▼────────┐
                        │ ExternalSecret  │
                        │     (ESO)       │
                        └─────────────────┘
```

---

## kagent CRDs (API Group: kagent.dev/v1alpha2)

### Agent

AI agent definition with tools and model configuration.

**Schema**:
```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: string            # Required: Agent name
  namespace: string       # Required: Deployment namespace
spec:
  type: string           # Required: "Declarative" | "BYO"
  description: string    # Optional: Human-readable description
  systemMessage: string  # Required: System prompt for the agent
  modelConfig:
    ref: string          # Required: Reference to ModelConfig resource name
  tools:                 # Optional: List of MCP tool references
    - ref: string        # MCPServer resource name
  memory:                # Optional: Agent memory configuration
    enabled: boolean
    maxMessages: integer
status:
  ready: boolean
  phase: string          # "Pending" | "Running" | "Ready" | "Failed"
  conditions: []         # Standard Kubernetes conditions
```

**Validation Rules**:
- `type` must be "Declarative" or "BYO"
- `modelConfig.ref` must reference existing ModelConfig
- `tools[].ref` must reference existing MCPServer resources

**State Transitions**:
- Pending → Running (controller picks up)
- Running → Ready (all tools available, model config valid)
- Running → Failed (invalid config or missing dependencies)

---

### ModelConfig

LLM provider configuration with credentials reference.

**Schema**:
```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: string
  namespace: string
spec:
  provider: string       # Required: "openai" | "anthropic" | "gemini" | "azure" | "ollama"
  model: string          # Required: Model identifier (e.g., "gpt-4", "claude-3-5-sonnet-20241022")
  apiKeySecretRef:
    name: string         # Required: Secret name containing API key
    key: string          # Required: Key within secret (e.g., "OPENAI_API_KEY")
  baseUrl: string        # Optional: Custom API endpoint
  temperature: number    # Optional: Model temperature (0.0 - 2.0)
  maxTokens: integer     # Optional: Maximum response tokens
status:
  ready: boolean
  lastValidated: timestamp
  error: string          # Error message if validation failed
```

**Validation Rules**:
- `provider` must be supported provider
- Secret referenced by `apiKeySecretRef` must exist
- API key must be valid (controller validates on creation)

---

### MCPServer

Model Context Protocol server deployment specification.

**Schema**:
```yaml
apiVersion: kagent.dev/v1alpha2
kind: MCPServer
metadata:
  name: string
  namespace: string
spec:
  deployment:
    image: string        # Required: Container image
    command: []string    # Optional: Entrypoint
    args: []string       # Optional: Arguments
    port: integer        # Required: Service port
    env:                 # Optional: Environment variables
      - name: string
        value: string
    envFrom:             # Optional: Environment from ConfigMap/Secret
      - secretRef:
          name: string
    resources:
      requests:
        cpu: string
        memory: string
      limits:
        cpu: string
        memory: string
  transportType: string  # Required: "stdio" | "http"
  httpTransport:         # Required if transportType=http
    path: string         # API path (e.g., "/mcp")
status:
  ready: boolean
  phase: string
  deploymentName: string # Created Deployment resource name
  serviceName: string    # Created Service resource name
  endpoint: string       # Internal service endpoint
```

**Validation Rules**:
- `image` must be valid container image reference
- `port` must be valid port number (1-65535)
- `transportType` must match transport configuration

**Lifecycle**:
- kmcp controller creates Deployment and Service resources
- Status updated with created resource names
- Endpoint provides internal DNS name for agents

---

## kgateway CRDs

### Gateway (Kubernetes Gateway API)

Standard Kubernetes Gateway API resource configured for kgateway.

**Schema** (relevant fields):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: string
  namespace: string
  annotations:
    kgateway.io/gateway-parameters: string  # Reference to GatewayParameters
spec:
  gatewayClassName: kgateway
  listeners:
    - name: string
      protocol: string     # "HTTP" | "HTTPS" | "TCP" | "TLS"
      port: integer
      hostname: string     # Optional: Hostname filter
      tls:                 # Optional: TLS configuration
        mode: string
        certificateRefs: []
status:
  addresses: []
  conditions: []
```

---

### HTTPRoute (Kubernetes Gateway API)

Routing rules for MCP traffic through agentgateway.

**Schema** (relevant fields):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: string
  namespace: string
spec:
  parentRefs:
    - name: string         # Gateway name
      namespace: string
  hostnames: []string      # Optional: Hostname matching
  rules:
    - matches:
        - path:
            type: string   # "PathPrefix" | "Exact"
            value: string
          headers: []      # Optional: Header matching
      backendRefs:
        - name: string     # Service name (MCP server)
          port: integer
          weight: integer  # Optional: Traffic weight
      filters: []          # Optional: Request/response transformation
status:
  parents: []
```

---

### GatewayParameters (kgateway-specific)

kgateway runtime configuration including OpenTelemetry.

**Schema**:
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: string
  namespace: string
spec:
  kube:
    aiExtension:
      enabled: boolean
      tracing:
        enabled: boolean
        endpoint: string   # OTel collector endpoint
        sampler:
          type: string     # "traceidratio" | "always_on" | "always_off"
          arg: string      # Sampling rate (0.0 - 1.0)
        protocol: string   # "grpc" | "http/protobuf"
        transportSecurity: string  # "plaintext" | "tls"
    deployment:
      replicas: integer
      resources:
        requests:
          cpu: string
          memory: string
        limits:
          cpu: string
          memory: string
```

---

## External Secrets CRD

### ExternalSecret

Azure Key Vault secret synchronization.

**Schema**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: string
  namespace: string
spec:
  refreshInterval: string  # e.g., "1h"
  secretStoreRef:
    name: string           # ClusterSecretStore name
    kind: string           # "ClusterSecretStore"
  target:
    name: string           # Target Kubernetes secret name
    creationPolicy: string # "Owner" | "Merge" | "None"
  data:
    - secretKey: string    # Key in target secret
      remoteRef:
        key: string        # Key name in Azure Key Vault
status:
  refreshTime: timestamp
  syncedResourceVersion: string
  conditions: []
```

---

## ArgoCD Application Resource

### Application

GitOps deployment unit.

**Schema** (Helm source):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: string
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: string  # Deployment order
spec:
  project: default
  source:
    repoURL: string        # Helm OCI registry URL
    chart: string          # Chart name
    targetRevision: string # Chart version
    helm:
      values: string       # Inline Helm values YAML
  destination:
    server: string         # Cluster API server
    namespace: string      # Target namespace
  syncPolicy:
    automated:
      prune: boolean
      selfHeal: boolean
    syncOptions: []string
status:
  health:
    status: string         # "Healthy" | "Degraded" | "Progressing"
  sync:
    status: string         # "Synced" | "OutOfSync"
```

---

## Relationships Summary

| Entity | References | Referenced By |
|--------|-----------|---------------|
| Agent | ModelConfig, MCPServer | - |
| ModelConfig | ExternalSecret (via secret) | Agent |
| MCPServer | - | Agent, HTTPRoute (backend) |
| Gateway | GatewayParameters | HTTPRoute |
| HTTPRoute | Gateway, MCPServer (service) | - |
| ExternalSecret | ClusterSecretStore | ModelConfig (via secret) |
| Application | - | - |

---

## Data Integrity Rules

1. **Cascade Dependencies**: ModelConfig must exist before Agent references it
2. **Secret Availability**: ExternalSecret must sync before ModelConfig validation
3. **Service Discovery**: MCPServer must create Service before HTTPRoute references it
4. **Gateway Readiness**: Gateway must be Ready before HTTPRoutes can bind
5. **Sync Wave Ordering**: ArgoCD Applications must respect sync wave dependencies
