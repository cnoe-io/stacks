# Feature Specification: Kargo Progressive Delivery Pipelines Framework

**Feature Branch**: `105-setup-kargo-pipelines`
**Created**: 2025-12-11
**Status**: Draft
**Input**: User description: "Create a new feature that creates a pipeline in kargo via cdk8s charts that can be a framework that promotes applications through our environments, kind, talos, (and a perhaps a future production environment); we should use our backstage application as the first example of a pipeline. Review kargo documentation to determine best practices around how to structure the kargo pipeline to accomplish our objectives. Also create a good mechanism for versioning of the docker images that represent our backstage application. Also review idpbuilder documentation to configure a rapid development cycle for the first stage of our process using kind, and gitea as the in-cluster git repo. The objective is to be able to quickly push a new image to gitea or similar, and that flow through to the kind kubernetes cluster, and then via promotion to the talos environment; review kargo best practices and any argocd integration, and consider the best gitops principles"

## Pipeline Architecture Overview

This feature implements a **parallel pipeline architecture** with two distinct loops optimized for different use cases:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Kargo Project: backstage                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  INNER LOOP (Local Development - Rapid Iteration)                           │
│  ┌────────────────┐        ┌────────────────┐                              │
│  │   Warehouse    │        │     Stage      │                              │
│  │   gitea-oci    │───────▶│   local-dev    │  (auto-promote, ephemeral)   │
│  │                │        │    (KIND)      │                              │
│  └────────────────┘        └────────────────┘                              │
│         │                                                                   │
│         │ Webhook: Gitea push → instant Freight                            │
│         │ Purpose: Sub-minute feedback for development                      │
│                                                                             │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
│                                                                             │
│  OUTER LOOP (Production Path - GitOps Flow)                                 │
│  ┌────────────────┐        ┌────────────────┐        ┌────────────────┐    │
│  │   Warehouse    │        │     Stage      │        │     Stage      │    │
│  │  github-ghcr   │───────▶│      dev       │───────▶│    staging     │───▶│
│  │                │        │    (KIND)      │        │    (Talos)     │    │
│  └────────────────┘        └────────────────┘        └────────────────┘    │
│         │                        │                          │              │
│         │                        │ (auto)              (manual)            │
│         │                        │                          │              │
│         │                        │                   ┌────────────────┐    │
│         │                        │                   │     Stage      │    │
│         │                        └──────────────────▶│   production   │    │
│         │                              (manual)      │    (future)    │    │
│         │                                            └────────────────┘    │
│         │                                                                   │
│         │ Webhook: GitHub Actions → CI-built images                        │
│         │ Purpose: Verified images flow to production                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Pipeline Comparison

| Aspect | Inner Loop (Gitea) | Outer Loop (GitHub) |
|--------|-------------------|---------------------|
| **Image Source** | Gitea OCI Registry (in-cluster) | GitHub Container Registry (GHCR) |
| **Trigger** | `docker push` to Gitea | GitHub Actions CI completion |
| **Auto-promote** | Always (to local-dev) | To dev stage only |
| **Target Clusters** | KIND only | KIND → Talos → Production |
| **Image Retention** | Ephemeral (lost on cluster rebuild) | Permanent (GHCR) |
| **Webhook Source** | Gitea (in-cluster, no TLS needed) | GitHub (external, TLS required) |
| **Use Case** | Rapid iteration, experimentation | Reviewed code, production path |
| **Quality Gate** | None (speed priority) | GitHub PR merge + CI build |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Inner Loop: Rapid Local Development with Gitea (Priority: P1)

A developer is iterating on Backstage changes locally. They build a new container image and push it directly to the Gitea OCI registry in the KIND cluster. Within seconds, the system detects the new image, creates Freight, and auto-promotes it to the local-dev stage, updating the running Backstage instance.

**Why this priority**: This is the fastest possible feedback loop. Developers can see their changes running in Kubernetes within a minute of pushing an image, without waiting for CI pipelines or code review.

**Independent Test**: Can be fully tested by pushing an image to Gitea and timing how quickly the KIND cluster's Backstage deployment updates. Target: under 60 seconds from push to running pod.

**Acceptance Scenarios**:

1. **Given** the Gitea Warehouse is configured to watch `gitea.cnoe.localtest.me:8443/giteaadmin/backstage`, **When** a developer pushes a new image tag, **Then** Freight is created within 30 seconds via webhook notification.
2. **Given** auto-promotion is enabled for the local-dev stage, **When** new Freight is available, **Then** it is immediately promoted without manual intervention.
3. **Given** the local-dev stage promotion completes, **When** ArgoCD syncs, **Then** the Backstage deployment in KIND uses the new image within 60 seconds of the original push.
4. **Given** the KIND cluster is rebuilt (idpbuilder delete/create), **When** the new cluster is ready, **Then** the inner loop pipeline is restored but previous Gitea images are not preserved (ephemeral by design).

---

### User Story 2 - Outer Loop: CI-Built Image Flows to Development (Priority: P1)

A developer merges a pull request to the main branch. GitHub Actions builds a new Backstage image and pushes it to GHCR. The system detects this CI-verified image and auto-promotes it to the dev stage in the KIND cluster.

**Why this priority**: This establishes the production-quality pipeline where only CI-built, reviewed images enter the promotion flow toward production environments.

**Independent Test**: Can be tested by merging a PR, waiting for GitHub Actions to complete, and verifying the KIND dev stage updates with the new GHCR image.

**Acceptance Scenarios**:

1. **Given** the GitHub Warehouse is configured to watch `ghcr.io/pittampalliorg/backstage`, **When** GitHub Actions pushes a new image tag after CI completion, **Then** Freight is created via GitHub webhook.
2. **Given** auto-promotion is enabled for the dev stage, **When** new Freight from the GitHub Warehouse is available, **Then** it is promoted to the dev stage automatically.
3. **Given** the dev stage runs in KIND, **When** promotion completes, **Then** the Backstage deployment uses the GHCR image (not Gitea image).
4. **Given** both inner and outer loop pipelines exist, **When** viewing Kargo UI, **Then** they appear as separate pipelines with independent Freight histories.

---

### User Story 3 - Outer Loop: Manual Promotion to Staging (Talos) (Priority: P2)

A platform engineer reviews the application running in the dev stage (KIND) and decides it is ready for staging. They manually promote the verified Freight to the staging stage, which deploys to the Talos cluster.

**Why this priority**: Manual promotion to staging provides a quality gate before changes reach the more stable Talos environment. This ensures human verification of dev testing.

**Independent Test**: Can be tested by manually triggering a promotion in Kargo UI/CLI and verifying the Talos cluster's Backstage deployment updates.

**Acceptance Scenarios**:

1. **Given** Freight has been deployed to the dev stage, **When** an operator requests promotion to staging, **Then** the Freight is promoted and the Talos cluster is updated.
2. **Given** the staging promotion is initiated, **When** it completes, **Then** the promotion history shows the operator identity and timestamp.
3. **Given** the Talos Backstage ArgoCD Application has the Kargo authorization annotation, **When** Kargo updates it, **Then** ArgoCD syncs the new image to Talos.

---

### User Story 4 - Webhook-Driven Instant Detection (Both Loops) (Priority: P2)

When images are pushed to either Gitea (inner loop) or GHCR (outer loop), webhooks notify Kargo immediately, eliminating polling latency and enabling sub-minute response times.

**Why this priority**: Webhooks are critical for the rapid feedback promised by the inner loop and significantly improve outer loop responsiveness.

**Independent Test**: Can be tested by measuring time from image push to Freight creation. With webhooks: under 30 seconds. Without webhooks (polling): 1-5 minutes.

**Acceptance Scenarios**:

1. **Given** Gitea is configured with a webhook to Kargo's in-cluster webhook receiver, **When** an image is pushed, **Then** Freight is created within 10 seconds.
2. **Given** GitHub is configured with a webhook to Kargo's external webhook endpoint, **When** GitHub Actions pushes an image, **Then** Freight is created within 30 seconds.
3. **Given** the external webhook endpoint requires TLS, **When** GitHub sends a webhook, **Then** the connection is secured with a valid certificate (via Tailscale or ingress-nginx).
4. **Given** webhook delivery fails, **When** the system falls back to polling, **Then** Freight is still created (within the polling interval).

---

### User Story 5 - Pipeline Visualization and Status Monitoring (Priority: P3)

A platform engineer views both pipelines (inner and outer loop) in the Kargo UI to understand the current state across all environments and development workflows.

**Why this priority**: Visibility into both pipelines is essential for operations but depends on the pipelines being functional first.

**Independent Test**: Can be tested by accessing Kargo UI and verifying both pipelines are visible with correct stage relationships.

**Acceptance Scenarios**:

1. **Given** both pipelines are configured, **When** viewing the Kargo dashboard, **Then** the inner loop (local-dev) and outer loop (dev → staging → production) are displayed separately.
2. **Given** Freight exists at different stages, **When** viewing either pipeline, **Then** each stage shows which Freight version is deployed.
3. **Given** the inner loop and outer loop have different images deployed, **When** comparing them, **Then** the version differences are clearly visible.

---

### User Story 6 - Graduating from Inner Loop to Outer Loop (Priority: P3)

A developer has validated their changes using the inner loop and is ready to create a PR. They push their code to GitHub, which triggers CI to build an "official" image. This image then flows through the outer loop.

**Why this priority**: This describes the developer workflow for transitioning from experimentation to production-bound code.

**Independent Test**: Can be tested by following the complete workflow: inner loop testing → PR creation → CI build → outer loop promotion.

**Acceptance Scenarios**:

1. **Given** a developer has tested changes via the inner loop, **When** they create a PR and it is merged, **Then** GitHub Actions builds a new image automatically.
2. **Given** the CI-built image is pushed to GHCR, **When** Kargo detects it, **Then** it enters the outer loop (not the inner loop).
3. **Given** the outer loop dev stage is updated, **When** comparing to local-dev, **Then** they may have different versions (inner loop may be ahead or behind).

---

### User Story 7 - Reusable Pipeline Framework for New Applications (Priority: P4)

A developer wants to add a new application to the promotion system. They use the established CDK8s chart patterns to create both inner and outer loop pipelines for the new application.

**Why this priority**: Framework extensibility requires the core dual-loop architecture to be proven first.

**Independent Test**: Can be tested by creating pipelines for a second application and verifying both loops function correctly.

**Acceptance Scenarios**:

1. **Given** the pipeline framework CDK8s charts exist, **When** creating a new application pipeline, **Then** both inner and outer loop resources are generated.
2. **Given** a new application is onboarded, **When** images are pushed to Gitea, **Then** the inner loop functions identically to Backstage.
3. **Given** multiple applications have pipelines, **When** viewing Kargo, **Then** each application's pipelines are independent and separately manageable.

---

### Edge Cases

- What happens when the image registry is unreachable? The Warehouse should retry discovery with exponential backoff and surface the error in its status.
- How does the system handle an image tag that references the same digest as a previous tag? Kargo should detect duplicate artifacts and avoid creating redundant Freight.
- What happens when a promotion fails due to ArgoCD sync errors? The promotion should fail with a clear error message, and the stage should remain at the previous Freight version.
- What happens when multiple Freight items are pending promotion? The system should promote the newest verified Freight by default, with configuration to change this behavior.
- How does the system handle rollback scenarios? Operators should be able to promote an older Freight version to revert a bad deployment.
- What happens when webhook delivery fails? The registry platform (Gitea/GitHub) should retry delivery with exponential backoff; the system should fall back to polling-based detection.
- What happens when a webhook arrives with an invalid signature? The system should reject the payload and log the authentication failure without processing.
- What happens when webhooks arrive out of order (newer image notification arrives before older)? The system should process both and let the promotion policy determine which Freight to promote.
- What happens when inner loop and outer loop have conflicting images in KIND? They target different ArgoCD Applications (backstage-local-dev vs backstage-dev), so they coexist independently.
- What happens when the KIND cluster is rebuilt? Inner loop state (Gitea images, local-dev deployments) is lost; outer loop state (GHCR images, dev/staging deployments) is preserved.

## Requirements *(mandatory)*

### Functional Requirements

#### Project and Infrastructure
- **FR-001**: System MUST create a Kargo Project namespace with proper labels (`kargo.akuity.io/project: "true"`) to contain all pipeline resources.
- **FR-002**: System MUST provide ServiceAccount and RBAC resources for Kargo to perform Git operations and ArgoCD updates.
- **FR-003**: System MUST store Git credentials and webhook secrets securely via External Secrets from Azure Key Vault.

#### Inner Loop (Gitea → local-dev)
- **FR-010**: System MUST configure a Warehouse (`gitea-oci`) that monitors the Gitea OCI registry for new Backstage images.
- **FR-011**: System MUST create a `local-dev` Stage targeting the KIND cluster's local development ArgoCD Application.
- **FR-012**: System MUST configure auto-promotion for the `local-dev` stage (all new Freight is immediately promoted).
- **FR-013**: System MUST configure Gitea webhooks to notify Kargo when images are pushed to the OCI registry.
- **FR-014**: System MUST handle Gitea's GitHub-compatible webhook payload format.

#### Outer Loop (GitHub → dev → staging → production)
- **FR-020**: System MUST configure a Warehouse (`github-ghcr`) that monitors GitHub Container Registry for CI-built Backstage images.
- **FR-021**: System MUST create a `dev` Stage targeting the KIND cluster's development ArgoCD Application (separate from local-dev).
- **FR-022**: System MUST create a `staging` Stage targeting the Talos cluster's staging ArgoCD Application.
- **FR-023**: System MUST create a `production` Stage (initially disabled/placeholder) for future production deployment.
- **FR-024**: System MUST configure auto-promotion for the `dev` stage only; staging and production require manual approval.
- **FR-025**: System MUST configure GitHub webhooks to notify Kargo when images are pushed to GHCR.
- **FR-026**: System MUST expose Kargo's external webhook server via a publicly accessible URL with valid TLS for GitHub delivery.

#### ArgoCD Integration
- **FR-030**: System MUST integrate with ArgoCD Applications via the `argocd-update` promotion step.
- **FR-031**: System MUST add `kargo.akuity.io/authorized-stage` annotations to ArgoCD Applications to authorize Kargo updates.
- **FR-032**: System MUST ensure stage health is derived from the associated ArgoCD Application health status.
- **FR-033**: System MUST configure promotion templates that update the image tag in the target environment's configuration.

#### Webhooks and Event Handling
- **FR-040**: System MUST configure webhook receivers in ProjectConfig for both Gitea and GitHub sources.
- **FR-041**: System MUST secure webhook endpoints with shared secrets to authenticate incoming payloads.
- **FR-042**: System MUST provide idempotent webhook processing to handle retries without creating duplicate Freight.
- **FR-043**: System MUST support falling back to polling-based detection when webhooks are unavailable.

#### Framework and Extensibility
- **FR-050**: System MUST provide CDK8s chart abstractions that can generate both inner and outer loop pipelines for new applications.
- **FR-051**: System MUST support semantic versioning patterns for image tags (e.g., `v1.2.3`, `sha-abc1234`).
- **FR-052**: System MUST support configurable image tag filters per Warehouse (e.g., ignore `latest`, only promote `v*` tags).

### Key Entities

- **Project**: A Kargo namespace containing related pipelines, governed by shared policies and RBAC.
- **Warehouse (gitea-oci)**: Watches Gitea OCI registry for locally-pushed images; feeds the inner loop.
- **Warehouse (github-ghcr)**: Watches GitHub Container Registry for CI-built images; feeds the outer loop.
- **Freight**: An immutable snapshot of versioned artifacts that moves through stages together.
- **Stage (local-dev)**: Inner loop target; ephemeral development environment in KIND for rapid iteration.
- **Stage (dev)**: Outer loop first stage; stable development environment in KIND for CI-verified images.
- **Stage (staging)**: Outer loop second stage; Talos cluster deployment for pre-production testing.
- **Stage (production)**: Outer loop final stage; future production environment (placeholder).
- **Promotion**: A request to transition a specific Freight into a Stage, executed via promotion steps.
- **ProjectConfig**: Configuration for project-wide settings including promotion policies and webhook receivers.
- **Webhook Receiver**: Configured endpoints in ProjectConfig for Gitea and GitHub push notifications.

## Success Criteria *(mandatory)*

### Measurable Outcomes

#### Inner Loop Performance
- **SC-001**: Developers can push an image to Gitea and see the local-dev stage updated within 60 seconds.
- **SC-002**: Freight is created within 10 seconds of Gitea webhook delivery.
- **SC-003**: The inner loop operates independently; KIND cluster rebuild does not affect outer loop state.

#### Outer Loop Performance
- **SC-010**: CI-built images from GHCR create Freight within 30 seconds of GitHub webhook delivery.
- **SC-011**: Auto-promotion to the dev stage completes within 2 minutes of Freight creation.
- **SC-012**: Manual promotion from dev to staging completes within 5 minutes of approval.

#### Operational
- **SC-020**: Platform engineers can promote verified changes with a single action (UI click or CLI command).
- **SC-021**: All promotion actions are visible in Kargo UI with operator identity, timestamp, and outcome.
- **SC-022**: Failed promotions clearly indicate the failure reason and do not leave environments in an inconsistent state.
- **SC-023**: Rollback to a previous version can be initiated within 2 minutes via Kargo UI or CLI.

#### Framework
- **SC-030**: Adding a new application to the pipeline framework requires fewer than 5 CDK8s resource definitions.
- **SC-031**: Both inner and outer loop pipelines are generated from a single application configuration.

#### Webhooks
- **SC-040**: Gitea webhooks are delivered in-cluster without requiring external TLS.
- **SC-041**: GitHub webhooks are delivered to a publicly accessible endpoint with valid TLS certificates.

## Assumptions

The following assumptions were made based on the codebase research and industry best practices:

1. **Dual ArgoCD Applications per Environment**: Each application will have separate ArgoCD Applications for inner loop (`backstage-local-dev`) and outer loop (`backstage-dev`) in KIND, preventing conflicts.

2. **Image Tagging Strategy**:
   - Inner loop: Uses commit-based tags (e.g., `dev-abc1234`) or timestamp tags for rapid iteration
   - Outer loop: Uses semantic versioning tags (e.g., `v1.2.3`) built by GitHub Actions

3. **Git Repository Structure**: Environment-specific manifests will be written to separate branches or paths to avoid feedback loops in Warehouse detection.

4. **ArgoCD Sync Mode**: ArgoCD Applications will use automated sync with self-heal enabled.

5. **Kargo Installation**: Kargo v1.8.x is already deployed with webhooks and controllers operational.

6. **Cluster Topology**:
   - KIND cluster runs ArgoCD (hub) and serves as the target for inner loop and outer loop dev stage
   - Talos cluster is managed remotely by ArgoCD for staging deployments

7. **External Secrets Operator**: ESO with Azure Key Vault integration is operational for Git credentials and webhook secrets.

8. **Gitea as Ephemeral**: The Gitea OCI registry is ephemeral and will be recreated with each KIND cluster rebuild. This is acceptable for the inner loop.

9. **GitHub Actions CI**: A GitHub Actions workflow exists that builds and pushes Backstage images to GHCR on PR merge.

## Non-Functional Considerations

- **Security**: Git credentials and webhook secrets must be managed via External Secrets. RBAC follows least-privilege principles. Webhook secrets are unique per source (Gitea vs GitHub).
- **Observability**: Promotion events are visible in Kargo UI and queryable via API. Both loops have independent audit trails.
- **Reliability**: Warehouse polling provides fallback when webhooks fail. Promotion failures do not corrupt environment state.
- **Scalability**: The framework supports 10+ application pipelines, each with both inner and outer loops.
- **Isolation**: Inner loop failures do not affect outer loop. Different applications' pipelines are independent.
