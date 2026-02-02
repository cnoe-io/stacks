# Dapr + Azure Integration Kustomize Component

Reusable kustomize component that provides Dapr + Azure App Configuration + Azure Key Vault integration for applications in the stacks repo.

## Overview

This component provides:
- **Azure Workload Identity** - ServiceAccount with Azure credentials (opt-in via `service-account` sub-component)
- **Dapr Configuration** - OTEL tracing and mTLS settings
- **ConfigMaps** - Base configuration for Dapr, OTEL, and Flipt feature flags
- **Optional Sub-Components** - Azure App Config, Redis statestore, Redis pubsub, External Secrets

## Directory Structure

```
dapr-azure-integration/
├── kustomization.yaml              # Main component definition
├── README.md                       # This file
├── base/
│   ├── ServiceAccount.yaml         # Workload Identity annotations (used by service-account sub-component)
│   ├── Configuration-dapr.yaml     # Dapr tracing + mTLS config
│   ├── ConfigMap-dapr.yaml         # Dapr feature flags base
│   ├── ConfigMap-otel.yaml         # OTEL settings base
│   └── ConfigMap-flipt.yaml        # Flipt settings base
├── service-account/
│   └── kustomization.yaml          # Opt-in ServiceAccount with Workload Identity
├── azure-app-config/
│   ├── kustomization.yaml
│   └── Component-azureappconfig.yaml
├── statestore-redis/
│   ├── kustomization.yaml
│   └── Component-statestore.yaml
├── pubsub-redis/
│   ├── kustomization.yaml
│   └── Component-pubsub.yaml
└── secrets/
    ├── kustomization.yaml
    └── ExternalSecret-core.yaml    # AI provider API keys
```

## What's Shared vs App-Specific

### Shared (Centralized in Component)

| Resource | Value |
|----------|-------|
| Azure Workload Identity | `client-id: 1140d9c2-...`, `tenant-id: 0c4da9c5-...` |
| Azure App Config host | `https://rg3-app-config.azconfig.io` |
| OTEL Collector endpoint | `otel-collector.observability.svc.cluster.local:4317` |
| Key Vault store ref | `ClusterSecretStore: azure-keyvault-store` |
| Dapr tracing/mTLS config | Shared settings |
| Flipt URL | `http://flipt.feature-flags.svc.cluster.local:8080` |

### App-Specific (Customized via Patches)

| Value | How Customized |
|-------|----------------|
| `namespace` | kustomize `namespace:` field |
| `app-id` (Dapr) | kustomize `namePrefix:` or patch |
| `label` (App Config filter) | Patch on Component |
| `OTEL_SERVICE_NAME` | ConfigMap patch |
| `Redis host` | Patch on statestore/pubsub |
| `scopes` (Dapr component) | Patch |

## Usage

### Basic Usage

Add the component to your app's kustomization.yaml:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-app
namePrefix: my-app-

# Include Dapr+Azure components (opt-in)
components:
  - ../../../dapr-azure-integration
  - ../../../dapr-azure-integration/service-account  # Include if you don't have your own ServiceAccount
  - ../../../dapr-azure-integration/azure-app-config
  - ../../../dapr-azure-integration/statestore-redis
  - ../../../dapr-azure-integration/pubsub-redis
  - ../../../dapr-azure-integration/secrets

resources:
  - Namespace.yaml
  - Deployment.yaml
  - Service.yaml

# App-specific customizations
patches:
  # Azure App Config label and scope
  - target:
      kind: Component
      name: azureappconfig
    patch: |
      - op: replace
        path: /spec/metadata/2/value
        value: "my-app"
      - op: replace
        path: /scopes/0
        value: "my-app"

  # OTEL service name
  - target:
      kind: ConfigMap
      name: otel-config
    patch: |
      - op: replace
        path: /data/OTEL_SERVICE_NAME
        value: "my-app"
      - op: replace
        path: /data/NEXT_PUBLIC_OTEL_SERVICE_NAME
        value: "my-app-browser"
      - op: replace
        path: /data/OTEL_RESOURCE_ATTRIBUTES
        value: "service.namespace=my-app,service.version=1.0.0"

  # Redis host for statestore
  - target:
      kind: Component
      name: statestore
    patch: |
      - op: replace
        path: /spec/metadata/0/value
        value: "redis.my-app.svc.cluster.local:6379"

  # Redis host for pubsub
  - target:
      kind: Component
      name: pubsub
    patch: |
      - op: replace
        path: /spec/metadata/0/value
        value: "redis.my-app.svc.cluster.local:6379"
```

### Minimal Usage (Base Only)

If you only need the base ServiceAccount and Dapr configuration:

```yaml
components:
  - ../../../dapr-azure-integration
```

### Adding App-Specific Secrets

The core ExternalSecret includes AI provider keys. Add app-specific secrets via patches:

```yaml
patches:
  - target:
      kind: ExternalSecret
      name: app-secrets
    patch: |
      - op: add
        path: /spec/data/-
        value:
          secretKey: AUTH_SECRET
          remoteRef:
            key: MY-APP-AUTH-SECRET
      - op: add
        path: /spec/target/template/data/AUTH_SECRET
        value: "{{ .AUTH_SECRET }}"
```

## Azure Setup Requirements

### Workload Identity

The component uses Azure Workload Identity. For new apps, add to the bootstrap script's `SA_CONFIGS`:

```bash
# In 00-bootstrap-azure-infra.sh
local -a SA_CONFIGS=(
    "external-secrets:external-secrets"
    "ai-chatbot:ai-chatbot"
    "my-new-app:my-new-app"  # Add new apps here
)
```

### Required Roles

The managed identity needs:
- **App Configuration Data Reader** on Azure App Configuration
- **Key Vault Secrets User** on Azure Key Vault

## Verification

1. **Build test**: `kustomize build packages/components/active-development/manifests/my-app/`
2. **Deploy test**: Apply to cluster and verify Dapr sidecar injection
3. **Runtime test**: Verify Azure App Config values are accessible via Dapr API

## Migration from Existing Apps

To migrate an existing app (like ai-chatbot):

1. Add component references to kustomization.yaml
2. Add patches for app-specific values
3. Remove duplicated resources that are now provided by the component:
   - ServiceAccount (if using component's SA)
   - Configuration-*-dapr.yaml
   - ConfigMap-dapr-config.yaml
   - ConfigMap-otel-config.yaml
   - ConfigMap-flipt-config.yaml
   - Component-azureappconfig.yaml (if using sub-component)
   - Component-statestore.yaml (if using sub-component)
   - Component-pubsub.yaml (if using sub-component)
4. Keep app-specific resources (subscriptions, infrastructure, etc.)
