# Data Model: Tailscale Services Migration

**Feature**: 101-improve-tailscale
**Date**: 2025-12-04

## Overview

This feature primarily involves configuration changes rather than data model changes. The key entities are Tailscale Services resources configured in the Tailscale Admin Console and CDK8s chart properties.

## Key Entities

### 1. Tailscale Service (Admin Console)

A stable service endpoint in the Tailscale control plane.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Service identifier (e.g., `svc:argocd-<cluster>`) |
| `description` | string | No | Human-readable description |
| `endpoints` | object[] | Yes | Port-protocol mappings |
| `endpoints[].protocol` | string | Yes | Transport protocol (`tcp`) |
| `endpoints[].port` | number | Yes | Exposed port (e.g., `443`) |

**Example**:
```
Name: svc:argocd-<cluster>
Description: ArgoCD GitOps Dashboard
Endpoints: tcp:443
```

### 2. ACL Auto-Approver (Admin Console)

Rules that automatically approve service registrations.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `serviceName` | string | Yes | Service to approve (e.g., `svc:argocd-<cluster>`) |
| `allowedTags` | string[] | Yes | Tags that can advertise this service |

**Example**:
```json
{
  "autoApprovers": {
    "services": {
      "svc:argocd-<cluster>": ["tag:k8s-services"]
    }
  }
}
```

### 3. Tagged Auth Key (Admin Console → Azure Key Vault)

Authentication key with ACL tags for service host devices.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | Yes | The auth key value |
| `reusable` | boolean | Yes | Must be `true` for multiple pods |
| `ephemeral` | boolean | Yes | Must be `true` for pod lifecycle |
| `tags` | string[] | Yes | ACL tags (e.g., `["tag:k8s-services"]`) |

**Storage**: Azure Key Vault secret `tailscale-auth-key`

### 4. TailscaleServeChartProps (CDK8s)

Chart properties for Tailscale serve deployments.

```typescript
interface TailscaleServeChartProps extends ChartProps {
  /** Service name for Tailscale Services (e.g., 'argocd') */
  serviceName: string;

  /** Backend service URL within cluster */
  backendUrl: string;

  /** Backend port (e.g., 443 for ArgoCD, 3000 for Langfuse) */
  backendPort: number;

  /** Secret name containing Tailscale auth key */
  authKeySecretName?: string; // default: 'tailscale-auth-key'

  /** Exposed HTTPS port (default: 443) */
  exposedPort?: number; // default: 443

  /** Whether backend uses self-signed cert */
  backendInsecure?: boolean; // default: false
}
```

**Current vs. Updated Props**:

| Property | Current | Updated | Notes |
|----------|---------|---------|-------|
| `serviceName` | N/A (hardcoded `hostname`) | Required | Drives `--service=svc:{name}` |
| `backendUrl` | Hardcoded | Configurable | Cluster service URL |
| `backendPort` | Hardcoded | Configurable | 8443, 3000, etc. |
| `exposedPort` | Implicit (443) | Explicit | For `--https={port}` |

## Entity Relationships

```
┌─────────────────────────────────────────────────────────────────┐
│                    Tailscale Admin Console                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐    approves    ┌──────────────────────┐   │
│  │ ACL Auto-       │───────────────▶│ Tailscale Service    │   │
│  │ Approvers       │                │ (svc:argocd-<cluster>) │   │
│  │ tag:k8s-services│                │ - tcp:443            │   │
│  └─────────────────┘                └──────────────────────┘   │
│                                              ▲                  │
│                                              │ advertises       │
│                                              │                  │
│  ┌─────────────────┐                         │                  │
│  │ Tagged Auth Key │─────────authenticates───┤                  │
│  │ tag:k8s-services│                         │                  │
│  └─────────────────┘                         │                  │
│         │                                    │                  │
└─────────│────────────────────────────────────│──────────────────┘
          │                                    │
          ▼                                    │
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐                ┌──────────────────────┐   │
│  │ Azure Key Vault │                │ CDK8s Chart Props    │   │
│  │ External Secret │                │ - serviceName        │   │
│  │ tailscale-auth- │                │ - backendUrl         │   │
│  │ key             │                │ - backendPort        │   │
│  └────────┬────────┘                └──────────┬───────────┘   │
│           │                                    │                │
│           ▼                                    ▼                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Tailscale Serve Pod                   │   │
│  │  - Uses auth key from secret                            │   │
│  │  - Runs: tailscale serve --service=svc:argocd-<cluster> │   │
│  │  - Proxies to backend cluster service                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## State Transitions

### Service Registration State Machine

```
┌─────────┐     auth key      ┌──────────────┐
│ Pod     │──────valid───────▶│ Device       │
│ Starting│                   │ Registered   │
└─────────┘                   └──────┬───────┘
                                     │
                                     │ tailscale serve --service
                                     ▼
┌─────────────────┐           ┌──────────────┐
│ Service         │◀──────────│ Service      │
│ Available       │  approved │ Advertised   │
│ (stable URL)    │           │ (pending)    │
└─────────────────┘           └──────────────┘
        │                            │
        │ pod deleted                │ auto-approver denies
        ▼                            ▼
┌─────────────────┐           ┌──────────────┐
│ Service         │           │ Service      │
│ Offline         │           │ Rejected     │
│ (URL preserved) │           │ (error)      │
└─────────────────┘           └──────────────┘
```

### Key State Transitions

| From | Event | To | Notes |
|------|-------|-----|-------|
| Pod Starting | Valid auth key | Device Registered | Device joins tailnet with tag |
| Device Registered | `tailscale serve --service` | Service Advertised | Service registration pending |
| Service Advertised | ACL auto-approver match | Service Available | Stable URL active |
| Service Advertised | ACL auto-approver deny | Service Rejected | Check tags/ACLs |
| Service Available | Pod deleted | Service Offline | URL preserved, reconnects on new pod |

## Validation Rules

### Tailscale Service Name
- Must start with `svc:` prefix
- Name portion: lowercase alphanumeric, hyphens allowed
- Example: `svc:argocd-ryzen`, `svc:langfuse-thinkpad`, `svc:k8s-api-ryzen`

### Auth Key
- Must have `reusable: true` for multiple pods
- Must have `ephemeral: true` for pod lifecycle
- Must have at least one tag matching ACL auto-approvers

### Backend URL
- Must be accessible from within the pod
- Format: `http://` or `https://` scheme
- For self-signed: use `https+insecure://`

## Migration Notes

### Breaking Changes
None - new service URLs coexist with existing device-hostname URLs during transition.

### Backward Compatibility
- Old device-hostname URLs (e.g., `argocd-ui-serve-3.tail286401.ts.net`) may exist but are not stable/predictable
- New stable URLs use Tailscale Services DNS: `https://argocd-<cluster>.tail286401.ts.net`
- Prefer migrating bookmarks/scripts to the stable service URLs
