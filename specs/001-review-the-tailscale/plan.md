# Implementation Plan: Tailscale Remote Kubernetes Cluster Access

**Branch**: `001-review-the-tailscale` | **Date**: 2025-10-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/home/vpittamp/stacks/specs/001-review-the-tailscale/spec.md`

## Summary

Enable secure remote access to Kubernetes cluster API server via Tailscale network using the Tailscale Kubernetes Operator. Implement identity-based access control mapping Tailscale user groups to Kubernetes RBAC permissions. Deploy operator and API server proxy using CDK8s TypeScript charts integrated with existing ArgoCD GitOps workflow. Support high-availability configurations with multi-replica proxy groups.

**Technical Approach**: Create CDK8s chart for Tailscale operator deployment, use Tailscale CLI to provision OAuth credentials and configure tailnet policy tags, generate Kubernetes manifests for operator and ProxyGroup resources, deploy via ArgoCD using standard idpbuilder workflow.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s infrastructure definition)
**Primary Dependencies**:
  - cdk8s (TypeScript Kubernetes manifest generation)
  - Tailscale Kubernetes Operator (Helm chart: tailscale/tailscale-operator)
  - Tailscale CLI (OAuth client and policy management)
  - ArgoCD (GitOps deployment)

**Storage**: N/A (operator state managed by Kubernetes, Tailscale credentials in External Secrets Operator)

**Testing**:
  - TypeScript compilation: `npm run compile`
  - Manifest synthesis: `cluster-synth`
  - Local deployment: `cluster-update` (idempotent)
  - kubectl connectivity verification from remote Tailscale-connected machine
  - ArgoCD CLI verification: `argocd app list --insecure`

**Target Platform**: Kubernetes 1.23.0+ (Kind cluster for local dev, production cluster for deployment)

**Project Type**: Infrastructure (CDK8s chart definition)

**Performance Goals**:
  - API proxy latency overhead <10% vs direct cluster access
  - Remote kubectl connection establishment <30 seconds
  - Zero-downtime HA proxy failover

**Constraints**:
  - Tailscale operator requires OAuth client with Devices Core + Auth Keys write scopes
  - ProxyGroup HA feature requires Tailscale Services (alpha) enablement
  - Operator and proxies should use matching versions (proxies up to 4 minor versions behind supported)
  - HTTPS must be enabled for tailnet

**Scale/Scope**:
  - Single Kubernetes cluster per operator deployment (dev environment only for initial implementation)
  - Support for multiple user groups with differentiated RBAC permissions
  - Single replica for dev, HA configurations deferred to production deployments

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ I. Type Safety First
**Compliant**: All infrastructure defined using TypeScript with CDK8s. No raw YAML templating. Leverages typed Kubernetes resource imports (`imports/k8s.ts`) and potential Tailscale CRD imports.

### ✅ II. GitOps-Native Design
**Compliant**: Manifests synthesized via CDK8s, committed to Git (via Gitea in local dev), deployed via ArgoCD. No direct kubectl apply for deployment.

### ✅ III. IdpBuilder Package Compatibility
**Compliant**: Chart will output to `cdk8s/dist/tailscale-operator/manifests/` with kustomization.yaml and ArgoCD Application manifest using `cnoe://tailscale-operator/manifests` URL.

### ✅ IV. Explicit Dependency Management
**Compliant**: Operator deployment will use sync wave annotations to ensure proper ordering:
  - Namespace: `-100`
  - CRDs: `-100`
  - Operator Deployment: `-90`
  - OAuth Secret (from ESO): `-80`
  - ProxyGroup: `0`

### ✅ V. Multi-Environment Configuration
**Compliant**: Chart will use parameterized TypeScript interface for environment-specific configuration:
  - `environmentName` prop for dev/staging/production
  - Conditional ProxyGroup deployment (HA in staging/production only)
  - Environment-specific replica counts

### ✅ VI. Secrets Management via External Systems
**Compliant**: Tailscale OAuth credentials stored in Azure Key Vault, synced via External Secrets Operator. No secrets in Git or manifests.

### ✅ VII. Local Testing and Validation
**Compliant**: Standard testing workflow:
  1. `cluster-synth` - TypeScript compilation and synthesis
  2. `cluster-update` - Deploy to local Kind cluster
  3. `argocd app list --insecure` - Verify deployment
  4. Remote kubectl test from Tailscale-connected machine
  5. `cluster-recreate` for clean validation

### ⚠️ VIII. Frontend Verification via Browser DevTools
**N/A**: This feature has no Web UI components. Tailscale operator is backend-only infrastructure.

### ✅ IX. Simplicity and YAGNI
**Compliant**: Single chart for operator deployment. No unnecessary abstractions. Leverages existing patterns (`eso-helpers.ts` for secrets, `argocd-sync-builders.ts` for annotations). ProxyGroup HA marked as optional (P3).

**GATE STATUS**: ✅ PASSED - All applicable principles compliant. No violations requiring justification.

## Project Structure

### Documentation (this feature)

```
specs/001-review-the-tailscale/
├── plan.md              # This file
├── research.md          # Tailscale operator deployment patterns
├── data-model.md        # Configuration entities (OAuth, ProxyGroup, grants)
├── quickstart.md        # Deployment and remote connection guide
├── contracts/           # Tailscale CLI command interfaces
│   └── tailscale-cli.md # OAuth creation, policy updates, kubeconfig generation
└── checklists/
    └── requirements.md  # Specification quality validation
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   └── infra/
│       └── tailscale-operator-chart.ts         # Main operator chart
├── config/
│   └── applications.ts                         # Add tailscale-operator config
├── lib/
│   ├── idpbuilder-chart-factory.ts            # Register TailscaleOperatorChart
│   ├── argocd-sync-builders.ts                # Sync wave helpers (existing)
│   └── eso-helpers.ts                         # OAuth secret pattern (existing)
└── imports/
    └── tailscale.com.ts                        # Tailscale CRDs (ProxyGroup, Connector)

cdk8s/dist/
└── tailscale-operator/
    ├── manifests/
    │   ├── Namespace.tailscale.k8s.yaml
    │   ├── Secret.tailscale-oauth.k8s.yaml     # ESO reference
    │   ├── Deployment.operator.k8s.yaml
    │   ├── ServiceAccount.operator.k8s.yaml
    │   ├── ClusterRole.operator.k8s.yaml
    │   ├── ClusterRoleBinding.operator.k8s.yaml
    │   ├── ProxyGroup.api-server.k8s.yaml      # Optional, for HA
    │   └── kustomization.yaml
    └── tailscale-operator.yaml                 # ArgoCD Application

.env-files/
└── wi.env                                      # OAuth client ID added here (non-secret)
```

**Structure Decision**: Infrastructure pattern following existing CDK8s organization. Chart located in `charts/infra/` alongside other infrastructure components (Vault, Dagger). Leverages existing helper libraries for secrets management and ArgoCD annotations. Tailscale CRDs imported via `npm run import` similar to Kargo and External Secrets CRDs.

## Complexity Tracking

*No complexity violations identified. Feature aligns with all applicable constitution principles.*
