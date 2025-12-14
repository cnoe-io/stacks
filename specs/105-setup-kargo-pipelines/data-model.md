# Data Model: Kargo Progressive Delivery Pipelines Framework

**Branch**: `105-setup-kargo-pipelines` | **Date**: 2025-12-11

## Overview

This document defines the Kargo CRD entities and their relationships for the parallel pipeline architecture.

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              kargo-pipelines (Namespace)                     │
│                                                                              │
│  ┌─────────────────┐                                                         │
│  │    Project      │◄──────────────────────────────────────────────────────┐ │
│  │ kargo-pipelines │                                                       │ │
│  └────────┬────────┘                                                       │ │
│           │                                                                │ │
│           ▼                                                                │ │
│  ┌─────────────────┐      ┌──────────────────┐     ┌──────────────────┐   │ │
│  │  ProjectConfig  │      │ Webhook Secrets  │     │   Credentials    │   │ │
│  │ kargo-pipelines │◄─────│ gitea-webhook    │     │ ghcr-credentials │   │ │
│  │                 │◄─────│ github-webhook   │     │ gitea-creds      │   │ │
│  └────────┬────────┘      └──────────────────┘     └──────────────────┘   │ │
│           │                                                                │ │
│           │ promotionPolicies                                              │ │
│           │ webhookReceivers                                               │ │
│           ▼                                                                │ │
│  ┌────────────────────────────────────────────────────────────────────┐   │ │
│  │                        INNER LOOP                                   │   │ │
│  │  ┌─────────────────┐         ┌─────────────────┐                   │   │ │
│  │  │   Warehouse     │────────▶│     Stage       │                   │   │ │
│  │  │ backstage-gitea │ Freight │ backstage-      │                   │   │ │
│  │  │                 │─────────│ local-dev       │                   │   │ │
│  │  └────────┬────────┘         └────────┬────────┘                   │   │ │
│  │           │                           │                             │   │ │
│  │           │ watches                   │ updates                     │   │ │
│  │           ▼                           ▼                             │   │ │
│  │  ┌─────────────────┐         ┌─────────────────┐                   │   │ │
│  │  │ Gitea Registry  │         │ ArgoCD App      │                   │   │ │
│  │  │ gitea:8443/     │         │ backstage-      │                   │   │ │
│  │  │ giteaadmin/     │         │ local-dev       │                   │   │ │
│  │  │ backstage       │         └─────────────────┘                   │   │ │
│  │  └─────────────────┘                                               │   │ │
│  └────────────────────────────────────────────────────────────────────┘   │ │
│                                                                            │ │
│  ┌────────────────────────────────────────────────────────────────────┐   │ │
│  │                        OUTER LOOP                                   │   │ │
│  │  ┌─────────────────┐         ┌─────────────────┐                   │   │ │
│  │  │   Warehouse     │────────▶│     Stage       │                   │   │ │
│  │  │ backstage-ghcr  │ Freight │ backstage-dev   │                   │   │ │
│  │  └────────┬────────┘─────────└────────┬────────┘                   │   │ │
│  │           │                           │                             │   │ │
│  │           │                           │ verified freight            │   │ │
│  │           │                           ▼                             │   │ │
│  │           │                  ┌─────────────────┐                   │   │ │
│  │           │                  │     Stage       │                   │   │ │
│  │           │                  │ backstage-      │                   │   │ │
│  │           │                  │ staging         │                   │   │ │
│  │           │                  └────────┬────────┘                   │   │ │
│  │           │                           │                             │   │ │
│  │           │                           │ verified freight            │   │ │
│  │           │                           ▼                             │   │ │
│  │           │                  ┌─────────────────┐                   │   │ │
│  │           │                  │     Stage       │                   │   │ │
│  │           │                  │ backstage-prod  │ (placeholder)     │   │ │
│  │           │                  └─────────────────┘                   │   │ │
│  │           │                                                        │   │ │
│  │           │ watches                                                │   │ │
│  │           ▼                                                        │   │ │
│  │  ┌─────────────────┐                                               │   │ │
│  │  │ GHCR Registry   │                                               │   │ │
│  │  │ ghcr.io/        │                                               │   │ │
│  │  │ pittampalliorg/ │                                               │   │ │
│  │  │ backstage       │                                               │   │ │
│  │  └─────────────────┘                                               │   │ │
│  └────────────────────────────────────────────────────────────────────┘   │ │
│                                                                            │ │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Entity Definitions

### 1. Project

**Purpose**: Defines a Kargo project namespace boundary.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `metadata.name` | string | Yes | Project name (must match namespace) |
| `metadata.namespace` | string | No | Namespace name (omit if same as name) |

**Validation Rules**:
- Name must be a valid Kubernetes namespace name
- Namespace must have label `kargo.akuity.io/project: "true"`

**State Transitions**: None (static resource)

---

### 2. ProjectConfig

**Purpose**: Project-wide configuration for promotion policies and webhook receivers.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `metadata.name` | string | Yes | Must match Project name |
| `metadata.namespace` | string | Yes | Must be in Project namespace |
| `spec.promotionPolicies` | array | No | Auto-promotion rules per stage pattern |
| `spec.webhookReceivers` | array | No | Webhook endpoint configurations |

**Promotion Policy Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `stageSelector.name` | string | Glob pattern for stage names (e.g., `glob:*-dev`) |
| `autoPromotionEnabled` | boolean | Whether to auto-promote new Freight |

**Webhook Receiver Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Receiver identifier |
| `github.secretRef.name` | string | Secret containing webhook shared secret |

---

### 3. Warehouse

**Purpose**: Monitors image registries for new artifacts and creates Freight.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `metadata.name` | string | Yes | Warehouse identifier |
| `metadata.namespace` | string | Yes | Must be in Project namespace |
| `spec.freightCreationPolicy` | string | Yes | `Automatic` or `Manual` |
| `spec.interval` | string | No | Polling interval (e.g., `5m0s`) |
| `spec.subscriptions` | array | Yes | Image subscriptions |

**Image Subscription Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `image.repoURL` | string | Yes | Registry URL without tag |
| `image.imageSelectionStrategy` | string | No | `SemVer`, `Lexical`, `Digest`, `NewestBuild` |
| `image.constraint` | string | No | SemVer constraint (e.g., `>=1.0.0`) |
| `image.allowTags` | string | No | Regex whitelist for tags |
| `image.ignoreTags` | array | No | Exact match blacklist |
| `image.discoveryLimit` | number | No | Max images to examine (default: 20) |
| `image.insecureSkipTLSVerify` | boolean | No | Skip TLS verification |

**Validation Rules**:
- `repoURL` must not include tag
- `allowTags` must be valid regex
- `constraint` must be valid semver constraint when strategy is `SemVer`

---

### 4. Stage

**Purpose**: Represents a deployment target in the promotion pipeline.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `metadata.name` | string | Yes | Stage identifier |
| `metadata.namespace` | string | Yes | Must be in Project namespace |
| `spec.requestedFreight` | array | Yes | Freight source configuration |
| `spec.promotionTemplate` | object | No | How to promote Freight |
| `spec.verification` | object | No | Post-promotion verification |

**Requested Freight Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `origin.kind` | string | Always `Warehouse` |
| `origin.name` | string | Warehouse name |
| `sources.direct` | boolean | Get Freight directly from Warehouse |
| `sources.stages` | array | Get Freight from upstream Stages |
| `sources.requiredSoakTime` | string | Minimum time in upstream stage |

**Promotion Template Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `spec.steps` | array | Promotion steps to execute |
| `spec.vars` | array | Variables for expression substitution |

**State Transitions**:
- `Waiting` → `Progressing` (promotion started)
- `Progressing` → `Healthy` (promotion succeeded)
- `Progressing` → `Failed` (promotion failed)

---

### 5. Freight

**Purpose**: Immutable snapshot of versioned artifacts.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `metadata.name` | string | Yes | Auto-generated unique ID |
| `metadata.namespace` | string | Yes | Project namespace |
| `spec.origin.kind` | string | Yes | `Warehouse` |
| `spec.origin.name` | string | Yes | Source Warehouse name |
| `spec.images` | array | No | Container images in this Freight |
| `spec.commits` | array | No | Git commits in this Freight |
| `spec.charts` | array | No | Helm charts in this Freight |

**Image Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `repoURL` | string | Image repository URL |
| `tag` | string | Image tag |
| `digest` | string | Image digest (sha256) |

**Validation Rules**:
- Freight is immutable once created
- At least one artifact type must be present

---

### 6. Promotion

**Purpose**: Request to move Freight into a Stage.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `metadata.name` | string | Yes | Promotion identifier |
| `metadata.namespace` | string | Yes | Project namespace |
| `spec.stage` | string | Yes | Target Stage name |
| `spec.freight` | string | Yes | Freight name to promote |
| `spec.steps` | array | No | Override promotion steps |

**State Transitions**:
- `Pending` → `Running` (controller picks up)
- `Running` → `Succeeded` (all steps completed)
- `Running` → `Failed` (step failed)
- `Running` → `Aborted` (user cancelled)

---

## Kargo CDK8s Type Mappings

| Entity | CDK8s Class | Import |
|--------|-------------|--------|
| Project | `Project` | `kargo.akuity.io` |
| ProjectConfig | `ProjectConfig` | `kargo.akuity.io` |
| Warehouse | `Warehouse` | `kargo.akuity.io` |
| Stage | `Stage` | `kargo.akuity.io` |
| Freight | `Freight` | `kargo.akuity.io` (read-only) |
| Promotion | `Promotion` | `kargo.akuity.io` (auto-created) |

---

## Instance Data for Backstage Pipeline

### Inner Loop Entities

| Entity | Name | Key Config |
|--------|------|------------|
| Warehouse | `backstage-gitea` | Watches `gitea:8443/giteaadmin/backstage` |
| Stage | `backstage-local-dev` | Auto-promote, direct from warehouse |

### Outer Loop Entities

| Entity | Name | Key Config |
|--------|------|------------|
| Warehouse | `backstage-ghcr` | Watches `ghcr.io/pittampalliorg/backstage` |
| Stage | `backstage-dev` | Auto-promote, direct from warehouse |
| Stage | `backstage-staging` | Manual promote, from `backstage-dev` |
| Stage | `backstage-prod` | Manual promote (placeholder) |

### Shared Entities

| Entity | Name | Key Config |
|--------|------|------------|
| Project | `kargo-pipelines` | Namespace for all pipelines |
| ProjectConfig | `kargo-pipelines` | Promotion policies, webhook receivers |

---

## Secrets

### Webhook Secrets

| Name | Key | Purpose |
|------|-----|---------|
| `kargo-gitea-webhook-secret` | `secret` | Authenticate Gitea webhooks |
| `kargo-github-webhook-secret` | `secret` | Authenticate GitHub webhooks |

### Registry Credentials (Optional)

| Name | Keys | Purpose |
|------|------|---------|
| `kargo-ghcr-credentials` | `username`, `password`, `repoURL` | GHCR private image access |

---

## Expression Variables

Available in promotion templates:

| Variable | Type | Description |
|----------|------|-------------|
| `.freight.images.0` | string | Full image reference (repo:tag) |
| `.freight.images.0.repoURL` | string | Image repository URL |
| `.freight.images.0.tag` | string | Image tag |
| `.freight.images.0.digest` | string | Image digest |
| `.vars.<name>` | any | User-defined variables |
| `.outputs.<step-alias>.<key>` | any | Output from previous steps |
