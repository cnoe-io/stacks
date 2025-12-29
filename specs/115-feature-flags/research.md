# Research: Feature Flagging System

**Feature**: 115-feature-flags | **Date**: 2025-12-29

## Executive Summary

This document captures research findings and technology decisions for implementing a CNCF-compliant feature flagging system. The recommended stack is **OpenFeature/flagd + Flipt**, providing a fully open-source solution with GitOps-native flag management.

---

## Decision 1: Feature Flag Evaluation Engine

### Decision: flagd (OpenFeature reference implementation)

**Rationale**:
- CNCF Incubating project with strong community backing
- Native OpenFeature SDK compatibility via gRPC and OFREP protocols
- Lightweight (~20MB container), minimal resource footprint
- Built-in OpenTelemetry integration for observability
- Supports multiple sync sources (file, HTTP, Kubernetes CRD, gRPC)
- Stateless design enables horizontal scaling

**Alternatives Considered**:

| Alternative | Pros | Cons | Rejection Reason |
|-------------|------|------|------------------|
| Unleash | Enterprise features, analytics | AGPL license, no official OpenFeature SDK | License concerns for internal platform |
| LaunchDarkly | Full-featured SaaS | Commercial, vendor lock-in | Not open-source |
| Split.io | Good SDK support | Commercial | Not open-source |
| Custom solution | Full control | Development overhead | Unnecessary complexity |

**Sources**:
- [flagd Official Documentation](https://flagd.dev/)
- [OpenFeature Project](https://openfeature.dev/)

---

## Decision 2: Flag Management UI

### Decision: Flipt v2 (Git-native feature management)

**Rationale**:
- 100% open-source (Apache 2.0 license)
- Git-native storage - flags are declarative YAML files
- OpenFeature compatible via OFREP protocol
- Built-in web UI for flag management
- Supports OIDC authentication (Keycloak integration)
- Kubernetes-native deployment (official Helm chart)
- Environment/namespace support for multi-env management

**Alternatives Considered**:

| Alternative | Pros | Cons | Rejection Reason |
|-------------|------|------|------------------|
| flagd only (no UI) | Minimal footprint | No management interface | Users need visual flag management |
| Unleash UI | Polished interface | AGPL license, database required | License and architecture mismatch |
| Custom UI | Tailored UX | Development time | Build vs buy - Flipt sufficient |
| ConfigMap editing | Native K8s | Poor UX, no audit trail | Not user-friendly |

**Sources**:
- [Flipt Documentation](https://docs.flipt.io/)
- [Flipt GitHub](https://github.com/flipt-io/flipt)
- [Flipt Helm Charts](https://helm.flipt.io/)

---

## Decision 3: Deployment Architecture

### Decision: Centralized flagd service (single Deployment with ClusterIP)

**Rationale**:
- Reduced resource consumption vs sidecar per pod
- Simplified configuration and updates
- Consistent flag evaluation across all services
- Single point for metrics/observability
- User clarification confirmed this preference

**Alternatives Considered**:

| Alternative | Pros | Cons | Rejection Reason |
|-------------|------|------|------------------|
| Sidecar injection | Pod isolation, no network hop | Resource overhead per pod | Excessive for current scale |
| In-process SDK | Lowest latency | Build-time flag bundling | Complex update workflow |
| Multiple flagd instances | Regional isolation | Configuration drift | Not needed for single cluster |

**Architecture Details**:
```
Applications ──gRPC:8013──► flagd Service ──sync──► Flipt/Git
              ──OFREP:8016──►
```

---

## Decision 4: Flag Configuration Storage

### Decision: Dedicated Git repository (`feature-flags`)

**Rationale**:
- Separation of concerns (flags vs infrastructure vs application code)
- PR-based workflows for flag changes
- Full audit trail via Git history
- Environment branching or directory structure support
- Flipt native Git backend integration
- User clarification confirmed this preference

**Alternatives Considered**:

| Alternative | Pros | Cons | Rejection Reason |
|-------------|------|------|------------------|
| ConfigMaps in stacks repo | Single repo | Mixed concerns, complex PRs | Flags change more frequently |
| Database (PostgreSQL) | CRUD operations | Not GitOps, persistence concerns | Architectural mismatch |
| Application repo | Co-located with code | Flag changes trigger app rebuilds | Decoupling needed |

**Repository Structure**:
```
feature-flags/
├── .flipt.yml              # Flipt configuration
├── flags/
│   ├── default.yaml        # Shared flag definitions
│   ├── development/        # Dev overrides
│   ├── staging/            # Staging overrides
│   └── production/         # Prod overrides
└── README.md
```

---

## Decision 5: Authentication & Authorization

### Decision: Keycloak OIDC with role-based namespaces

**Rationale**:
- Existing Keycloak infrastructure (FR-004)
- SSO across platform tools (Backstage, ArgoCD, etc.)
- Role claim mapping for RBAC enforcement
- Flipt native OIDC support

**Role Mapping** (per FR-015):

| Keycloak Role | Flipt Namespace Access | Actions |
|---------------|------------------------|---------|
| `developer` | development, staging | read, write |
| `platform-team` | all (including production) | read, write, delete |
| `viewer` | all | read only |

**Implementation**:
- Create `flipt` client in `cnoe` realm
- Map realm roles to Flipt namespace permissions
- Client secret stored in Azure Key Vault, synced via ESO

---

## Decision 6: Observability Integration

### Decision: Native OpenTelemetry with existing collector

**Rationale**:
- flagd has built-in OTLP exporter
- Flipt supports metrics export
- Existing OpenTelemetry Collector infrastructure
- Grafana dashboards for visualization

**Metrics Exposed**:

| Metric | Source | Description |
|--------|--------|-------------|
| `feature_flag_evaluation_count` | flagd | Total evaluations by flag/variant |
| `feature_flag_evaluation_latency` | flagd | Evaluation duration histogram |
| `feature_flag_evaluation_error` | flagd | Errors by flag/reason |
| `flipt_evaluations_total` | Flipt | UI-initiated evaluations |

**Configuration**:
```yaml
# flagd OTEL config
otel:
  exporter:
    grpc:
      endpoint: otel-collector.observability.svc:4317
      insecure: true
```

---

## Decision 7: SDK Strategy

### Decision: OpenFeature SDKs with flagd provider

**Rationale**:
- Vendor-neutral abstraction
- Consistent API across languages
- Future flexibility to swap backends
- Strong community support

**SDK Availability**:

| Language | SDK | Provider | Services Using |
|----------|-----|----------|----------------|
| Go | go-sdk | flagd-provider | CAIPE agents, custom controllers |
| TypeScript | server-sdk | flagd-provider | Backstage plugins |
| Python | python-sdk | flagd-provider | ML pipelines |
| Java | java-sdk | flagd-provider | Future services |

**Connection Configuration**:
```
Host: flagd.feature-flags.svc.cluster.local
Port: 8013 (gRPC) or 8016 (OFREP)
TLS: false (internal cluster)
```

---

## Decision 8: Multi-Environment Strategy

### Decision: Flipt namespaces mapped to environments

**Rationale**:
- Flipt native namespace support
- Directory-based Git structure
- Environment isolation in single Flipt instance
- RBAC ties namespaces to roles

**Environment Mapping**:

| Environment | Flipt Namespace | Git Path | Cluster |
|-------------|-----------------|----------|---------|
| development | `development` | `flags/development/` | kind |
| staging | `staging` | `flags/staging/` | thinkpad |
| production | `production` | `flags/production/` | talos |

**Hub-and-Spoke Consideration**:
- Single Flipt instance on hub cluster
- Spoke clusters connect to hub flagd via Tailscale
- Or: Deploy flagd per spoke with Git sync (no Flipt UI)

---

## Technical Specifications

### flagd Configuration

```yaml
# flagd deployment config
image: ghcr.io/open-feature/flagd:v0.10.4
ports:
  - 8013  # gRPC evaluation
  - 8014  # Sync (internal)
  - 8015  # Metrics
  - 8016  # OFREP HTTP
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```

### Flipt Configuration

```yaml
# flipt deployment config
image: flipt/flipt:v2.5.0
ports:
  - 8080  # HTTP (UI + API)
  - 9000  # gRPC (optional)
storage:
  type: git
  git:
    repository: https://gitea.cnoe.localtest.me/feature-flags/feature-flags.git
    ref: main
    pollInterval: 30s
authentication:
  required: true
  methods:
    - oidc:
        clientId: flipt
        issuerUrl: https://keycloak.cnoe.localtest.me/realms/cnoe
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| flagd unavailability | Low | Medium | SDK fallback to default values, HPA scaling |
| Git sync failure | Low | Low | Flipt caches last known state |
| Keycloak outage | Low | Medium | Cached sessions, flag evaluation unaffected |
| Flag misconfiguration | Medium | High | PR review, staging validation, rollback via Git |
| Performance degradation | Low | Medium | Horizontal scaling, caching |

---

## References

- [OpenFeature Specification](https://openfeature.dev/specification/)
- [flagd Architecture](https://flagd.dev/architecture/)
- [Flipt Self-Hosted Guide](https://docs.flipt.io/operations/deployment)
- [OFREP Protocol](https://flagd.dev/reference/flagd-ofrep/)
- [OpenFeature Operator Quick Start](https://openfeature.dev/docs/tutorials/open-feature-operator/quick-start/)
