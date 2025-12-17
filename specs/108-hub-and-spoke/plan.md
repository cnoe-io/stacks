# Implementation Plan: Hub-and-Spoke ArgoCD with Dedicated Talos Hub Cluster

**Branch**: `108-hub-and-spoke` | **Date**: 2025-12-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/108-hub-and-spoke/spec.md`

## Summary

Provision a dedicated single-node Talos Linux cluster on Hetzner Cloud as an ArgoCD hub for centralized multi-cluster management. The hub runs only management workloads (ArgoCD, Kargo, ESO, Tailscale operator) while application workloads run on spoke clusters (hetzner, thinkpad, ryzen, talos). CDK8s charts generate ArgoCD cluster secrets and Applications with `targetCluster` field for spoke targeting, using rendered manifests pattern committed to Git.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s), Bash (provisioning scripts)
**Primary Dependencies**: CDK8s, cdk8s-plus-32, ArgoCD v7.3.0, Kargo v1.8.4, External Secrets Operator, Tailscale Operator
**Storage**: etcd (single-node hub), Azure Key Vault (secrets), Git (manifests)
**Testing**: `npm run compile` (type check), `kubectl diff` (dry-run), ArgoCD sync validation
**Target Platform**: Talos Linux 1.11.5, Kubernetes 1.32.0, Hetzner Cloud CX32
**Project Type**: Infrastructure-as-Code (CDK8s GitOps platform)
**Performance Goals**: Hub provisioned <30min, spoke registration <15min, app deployment <2min
**Constraints**: Hub cost <€15/mo, single-node (no HA), Tailscale-only access
**Scale/Scope**: 1 hub cluster, 4 spoke clusters, ~100 applications total

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type-Safe Infrastructure | ✅ PASS | CDK8s TypeScript, single main.ts, cluster-type-driven synthesis |
| II. GitOps-First Deployment | ✅ PASS | ArgoCD hub manages all spokes, rendered manifests in Git |
| III. Multi-Environment Isolation | ✅ PASS | Hub isolated from workloads, spokes handle app environments |
| IV. Declarative Configuration | ✅ PASS | applications.ts with targetCluster, ExternalSecrets for credentials |
| V. CNOE Technology Alignment | ✅ PASS | ArgoCD, Kargo, ESO, Tailscale - all CNOE-endorsed |
| VI. Package-Based Architecture | ✅ PASS | Each spoke registration as package, kustomization.yaml generated |
| VII. Security by Default | ✅ PASS | ESO for secrets, Tailscale-only access, no public K8s API |
| VIII. AI-Augmented Platform | N/A | No AI agents on hub (management-only) |
| IX. Unified Cluster Bootstrap | ✅ PASS | Reuses talos-cluster patterns, CLUSTER_TYPE-driven synthesis |
| X. Immutable Infrastructure | ✅ PASS | Talos API-only management, no SSH |
| XI. High Availability & DR | ⚠️ JUSTIFIED | Single-node hub (cost constraint); recovery documented in spec |
| XII. Upgrade & Rollback | ✅ PASS | Talos upgrade sequence applies, GitOps enables rollback |
| XIII. Observability & Monitoring | ⚠️ DEFERRED | Basic ArgoCD metrics; full stack deferred to future feature |

**Justifications for Non-Pass Items:**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Single-node hub (Principle XI) | Cost constraint (<€15/mo); hub failure doesn't affect spoke workloads | 3-node HA hub costs ~€45/mo; spoke isolation provides acceptable resilience |
| Deferred observability (Principle XIII) | Focus on core hub-spoke functionality first | Full Prometheus/Grafana stack adds complexity; ArgoCD UI provides basic health |

## Project Structure

### Documentation (this feature)

```
specs/108-hub-and-spoke/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── argocd-cluster-secret.yaml
│   ├── spoke-serviceaccount.yaml
│   └── application-config-schema.ts
├── checklists/
│   └── requirements.md  # Spec quality checklist (complete)
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```
# Hub Cluster Provisioning (talos-cluster repo)
talos-cluster/
├── patches/
│   ├── common.yaml                    # Shared node config
│   ├── controlplane/
│   │   └── hub.yaml                   # Hub-specific CP config (NEW)
│   └── worker/                        # N/A for single-node hub
├── scripts/
│   ├── provision-hub.sh               # Hub infrastructure script (NEW)
│   ├── gen-hub-config.sh              # Hub machine config generator (NEW)
│   └── bootstrap-hub.sh               # Hub cluster bootstrap (NEW)
└── secrets/
    └── hub-secrets.yaml               # Hub cluster secrets (encrypted)

# CDK8s Charts (stacks repo)
cdk8s/
├── charts/
│   ├── platform/
│   │   ├── argocd-cluster-secret-chart.ts      # (NEW) Spoke registration
│   │   ├── argocd-hub-application-chart.ts     # (NEW) Hub-aware app generation
│   │   └── argo-applications-chart-v2.ts       # (MODIFY) Add targetCluster support
│   └── secrets/
│       └── argocd-cluster-credentials-chart.ts # (NEW) ESO for spoke creds
├── config/
│   └── applications.ts                          # (MODIFY) Add targetCluster field
├── lib/
│   ├── idpbuilder-types.ts                     # (MODIFY) ApplicationConfig type
│   └── cluster-registry.ts                     # (NEW) Spoke cluster helpers
└── dist/
    ├── argocd-cluster-hetzner/                 # (NEW) Hetzner spoke registration
    ├── argocd-cluster-thinkpad/                # (NEW) Thinkpad spoke registration
    ├── argocd-cluster-ryzen/                   # (NEW) Ryzen spoke registration
    └── argocd-cluster-talos/                   # (NEW) Talos spoke registration

# Spoke Bootstrap Scripts (stacks repo)
scripts/
├── bootstrap-spoke.sh                          # (NEW) Spoke ServiceAccount setup
└── lib/
    └── spoke-helpers.sh                        # (NEW) Spoke registration helpers
```

**Structure Decision**: Infrastructure-as-Code project using existing talos-cluster repo for hub provisioning and stacks repo CDK8s charts for GitOps configuration. No new top-level directories; extends existing patterns.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Single-node hub (Principle XI) | Cost constraint (<€15/mo); hub failure doesn't affect spoke workloads | 3-node HA hub costs ~€45/mo; spoke isolation provides acceptable resilience |
| Deferred observability (Principle XIII) | Focus on core hub-spoke functionality first | Full Prometheus/Grafana stack adds complexity; ArgoCD UI provides basic health |

## Implementation Phases

### Phase 0: Research (Complete)

See [research.md](./research.md) for:
- ArgoCD cluster secret format and multi-cluster patterns
- Talos single-node cluster configuration
- Kargo cross-cluster promotion patterns
- Tailscale service mesh connectivity

### Phase 1: Design (Complete)

See:
- [data-model.md](./data-model.md) - Entity definitions
- [contracts/](./contracts/) - API contracts and schemas
- [quickstart.md](./quickstart.md) - Step-by-step deployment guide

### Phase 2: Tasks (via /speckit.tasks)

Implementation tasks will be generated by `/speckit.tasks` command after Phase 1 artifacts are reviewed.

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| Feature 100 (talos-cluster) | ✅ Complete | Provisioning patterns ready |
| Feature 102 (bootstrap-talos-argocd) | ✅ Complete | ArgoCD bootstrap patterns ready |
| Feature 103 (tailscale-services) | ✅ Complete | Service URL patterns ready |
| Feature 105 (kargo-pipelines) | ✅ Complete | Pipeline architecture ready |
| Azure Key Vault | ✅ Available | Secrets storage ready |
| Tailscale Tailnet | ✅ Available | Mesh connectivity ready |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Hub single point of failure | Document recovery procedure; spoke workloads unaffected by hub downtime |
| Credential expiration | External Secrets auto-refresh; monitoring for sync failures |
| Tailscale connectivity | DERP relay fallback; multiple NAT traversal paths |
| Resource exhaustion | Monitor hub resources; upgrade to CX32 if CX22 insufficient |
