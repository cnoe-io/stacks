# Implementation Plan: Backstage CDK8s Chart Migration

**Branch**: `104-backstage-talos` | **Date**: 2025-12-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/104-backstage-talos/spec.md`

## Summary

Migrate the Backstage idpBuilder custom package (`ref-implementation/backstage/`) to CDK8s TypeScript charts that synthesize equivalent YAML manifests. This enables type-safe infrastructure, IDE support, and unified deployment across KIND and Talos clusters. Two charts will be created: `BackstageChart` for workload resources and `BackstageSecretsChart` for External Secrets.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s framework)
**Primary Dependencies**: cdk8s, cdk8s-cli, constructs, glob
**Storage**: PostgreSQL StatefulSet with PVC (500Mi), defined in BackstageChart
**Testing**: Manual synthesis validation (`npm run synth`) + `kubectl diff` against ref-implementation
**Target Platform**: Kubernetes (KIND for local dev, Talos for production)
**Project Type**: Single project (extends existing cdk8s structure)
**Performance Goals**: Synthesis completes in <30 seconds for all applications
**Constraints**: Manifests must be semantically equivalent to ref-implementation YAML
**Scale/Scope**: 2 new chart files, ~400 lines total, 21 Kubernetes resources

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Note**: No constitution.md found in repository. Proceeding without constitution gates.

| Gate | Status | Notes |
|------|--------|-------|
| Chart file naming | ✅ PASS | Uses `-chart.ts` suffix for auto-registration |
| Namespace isolation | ✅ PASS | All resources in `backstage` namespace |
| Sync-wave ordering | ✅ PASS | Follows established patterns: -10, 10, 20 |
| Helper library usage | ✅ PASS | Uses eso-helpers.ts, argocd-sync-builders.ts |
| Type imports | ✅ PASS | Uses imports/k8s.ts, imports/external-secrets.io.ts |
| ClusterType support | ✅ PASS | Configuration includes clusterType field |

## Project Structure

### Documentation (this feature)

```
specs/104-backstage-talos/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output - testing guide
├── contracts/           # Phase 1 output - resource schemas
│   └── backstage-resources.yaml
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   ├── apps/
│   │   └── backstage-chart.ts           # NEW: BackstageChart class
│   └── secrets/
│       └── backstage-secrets-chart.ts   # NEW: BackstageSecretsChart class
├── config/
│   └── applications.ts                  # MODIFY: Add backstage configs
├── imports/
│   ├── k8s.ts                           # Kubernetes types (existing)
│   └── external-secrets.io.ts           # ESO CRDs (existing)
├── lib/
│   ├── eso-helpers.ts                   # ExternalSecret helpers (existing)
│   └── argocd-sync-builders.ts          # Sync-wave helpers (existing)
└── main.ts                              # Entry point (unchanged - auto-registers)

ref-implementation/
├── backstage/
│   └── manifests/
│       ├── install.yaml                 # Source manifests to replicate
│       └── argocd-secrets.yaml          # Source secrets to replicate
└── backstage-templates/                 # Templates (out of scope for P1)
```

**Structure Decision**: Extends existing cdk8s chart structure. Charts in `charts/apps/` and `charts/secrets/` follow established patterns. Auto-registration via `lib/auto-register-charts.ts` means no manual imports needed in main.ts.

## Complexity Tracking

*No violations detected - implementation follows established patterns*

| Aspect | Complexity | Justification |
|--------|------------|---------------|
| Two charts | Low | Separation of concerns: workloads vs secrets |
| Resource count (21) | Medium | Equivalent to existing ref-implementation |
| Helper usage | Low | Reuses existing eso-helpers.ts patterns |

## Implementation Phases

### Phase 0: Research (Complete)

See [research.md](./research.md) for:
- Existing chart patterns (HeadlampChart, KagentSecretsChart)
- ESO helper usage patterns
- Sync-wave annotation conventions
- ClusterSecretStore dependencies

### Phase 1: Design Artifacts

1. **data-model.md**: Document resource specifications and relationships
2. **contracts/backstage-resources.yaml**: Define expected synthesized resources
3. **quickstart.md**: Testing and validation guide

### Phase 2: Task Generation

Generated via `/speckit.tasks` command after plan approval.

## Key Design Decisions

### 1. Chart Separation

**Decision**: Separate BackstageChart and BackstageSecretsChart
**Rationale**: Follows established pattern (HeadlampChart + HeadlampKeycloakSecretsChart). Enables different sync-waves and independent secret management.

### 2. Secret Store Dependencies

**Decision**: BackstageSecretsChart creates ArgoCD ClusterSecretStore
**Rationale**: Required for argocd-credentials ExternalSecret. ArgoCD ClusterSecretStore uses in-cluster Kubernetes provider pattern.

### 3. Sync-Wave Ordering

**Decision**:
- backstage-secrets: sync-wave "-10" (ArgoCD Application level)
- ghcr-dockercfg-external: sync-wave "-10" (resource level)
- postgresql StatefulSet: sync-wave "10"
- backstage Deployment: sync-wave "20"

**Rationale**: Matches ref-implementation timing. Secrets must exist before deployments reference them.

### 4. Environment Variables

**Decision**: Use `process.env` for configurable values (INGRESS_HOST, KEYCLOAK_URL)
**Rationale**: Follows HeadlampChart pattern. Enables environment-specific customization.

### 5. Image Pull Secret

**Decision**: BackstageSecretsChart creates ghcr-dockercfg using existing createDockerConfigJsonExternalSecret helper
**Rationale**: Reuses established eso-helpers.ts pattern. Pulls GITHUB-PAT from Azure Key Vault.
