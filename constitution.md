<!--
SYNC IMPACT REPORT - 2025-12-07

Version Change: 1.2.0 → 1.3.0
- Minor version bump: Integrated elements from talos-cluster constitution

Modified Principles:
- Principle VII (Security by Default): Added mTLS, certificate rotation, SOPS encryption patterns
- Principle IX (Unified Cluster Bootstrap): Added Talos-specific talosctl commands and patterns

Added Sections:
- Principle X: Immutable Infrastructure for Talos (NEW - from talos-cluster)
- Principle XI: High Availability & Disaster Recovery (NEW - from talos-cluster)
- Principle XII: Upgrade & Rollback Discipline (NEW - from talos-cluster)
- Principle XIII: Observability & Monitoring (NEW - from talos-cluster)
- Tailscale Network Security section with ACL patterns
- Certificate rotation schedule
- SOPS encryption pattern for Talos secrets

Removed Sections:
- None

Templates Status:
✅ plan-template.md - Constitution Check section aligns with all 13 principles
✅ spec-template.md - Requirements structure supports functional requirements for all principles
✅ tasks-template.md - Task organization supports infrastructure, security, GitOps, HA, and monitoring
⚠ Commands in .specify/templates/commands/ - Need verification for Talos patterns

Follow-up TODOs:
- Verify cluster-menu.sh references after main.ts migration
- Update CLAUDE.md synthesis section after feature implementation
- Add talosctl command reference to CLAUDE.md for Talos clusters

Rationale for Version 1.3.0:
- MINOR version: Four new principles added from talos-cluster constitution
- Material expansion of Principle VII (Security) with mTLS and certificate patterns
- Material expansion of Principle IX (Bootstrap) with talosctl commands
- Integrates operational excellence patterns for Talos production clusters
- Adds HA, upgrade discipline, and observability requirements
-->

# Stacks CDK8s GitOps Platform Constitution

## Core Principles

### I. Type-Safe Infrastructure as Code (TypeScript over YAML Templating)

All Kubernetes manifests MUST be defined using CDK8s with TypeScript, not YAML templating (Helm, Kustomize).

**Rationale**: Type safety provides compile-time validation, IDE autocomplete, refactoring capabilities, and eliminates entire classes of YAML syntax/indentation errors. TypeScript enables reusable functions, libraries, and complex logic that YAML templating cannot achieve.

**Requirements**:
- Use `imports/k8s` (low-level API) for exact YAML control and CRD definitions
- Use `cdk8s-plus-32` (high-level API) selectively when ergonomics improve productivity without altering YAML semantics
- All resource definitions MUST pass TypeScript type checking before synthesis
- Chart classes MUST extend `Chart` from `cdk8s` library
- Resource naming MUST follow pattern: `<app>-<env>-<resource>`
- **Unified Entry Point**: Synthesis MUST use a single `main.ts` entry point with `CLUSTER_TYPE` environment variable for cluster-specific behavior

**Enforcement**:
- Run `npm run compile` or `npx tsc --noEmit` before synthesis
- CI/CD pipeline MUST fail on TypeScript compilation errors
- Code reviews MUST reject raw YAML manifests in `cdk8s/` directory
- Code reviews MUST reject cluster-specific entry points (use single `main.ts`)

### II. GitOps-First Deployment

All platform services and applications MUST be deployed via ArgoCD using GitOps patterns. No imperative `kubectl apply` commands for production resources. All idpbuilder operations MUST use the cluster-menu.sh wrapper scripts.

**Rationale**: GitOps ensures declarative, version-controlled, auditable infrastructure. ArgoCD provides automatic sync, drift detection, and rollback capabilities. The `cnoe://` URL syntax enables local development with the same GitOps workflow as production. The cluster-menu.sh scripts provide consistent, idempotent cluster management with proper flag handling and environment configuration.

**Requirements**:
- Every application MUST have an ArgoCD Application manifest in `cdk8s/dist/<app>.yaml`
- **Cluster-Type-Driven Sources**:
  - `CLUSTER_TYPE=kind`: ArgoCD Application sources MUST use `cnoe://<package>/manifests` format
  - `CLUSTER_TYPE=talos`: ArgoCD Application sources MUST use GitHub repository URLs with manifest paths
- Source URL generation MUST use centralized `cdk8s/lib/source-url.ts` utility
- Sync waves MUST control resource ordering:
  - `-120` to `-100`: CRDs, Namespaces
  - `-90` to `-80`: RBAC, ServiceAccounts
  - `-70` to `-50`: Secrets, ConfigMaps
  - `0` to `50`: Deployments, StatefulSets
  - `60+`: Applications, Ingresses
- Sync policy MUST specify `automated.prune` and `automated.selfHeal` for production
- **Cluster Operations**:
  - MUST use `cluster-update` for deploying/updating manifests (never raw `idpbuilder create`)
  - MUST use `cluster-recreate` for full cluster recreation
  - MUST use `cluster-synth` for synthesis-only operations
  - Direct `idpbuilder` commands are ONLY allowed when cluster-menu.sh functions don't cover the use case
  - cluster-menu.sh automatically handles StaticPassword flags, environment variables, and CDK8s synthesis
- **ArgoCD CLI Operations**:
  - MUST use `--insecure` flag for all local development commands (self-signed certificates)
  - MUST source `deployment/scripts/cluster-menu.sh` for automatic `ARGOCD_AUTH_TOKEN` setup
  - Use helper functions (`argocd-status`, `argocd-sync`, `argocd-list-outofsync`) when available
  - See `deployment/docs/ARGOCD_AUTOMATION.md` for automation patterns

**Enforcement**:
- Production environments MUST reject direct `kubectl apply` (enforced via RBAC/OPA)
- All Application manifests MUST include `argocd.argoproj.io/sync-wave` annotations
- CI validation MUST verify ArgoCD Application manifests synthesize correctly
- Documentation MUST reference cluster-menu.sh functions instead of raw idpbuilder commands
- Synthesis MUST fail if `CLUSTER_TYPE` is set to unsupported value

### III. Multi-Environment Isolation

Development and staging environments MUST use VClusters for logical isolation. Production environments MUST use dedicated physical clusters or namespaces with strict RBAC.

**Rationale**: VClusters provide full Kubernetes API isolation without the overhead of separate physical clusters, enabling safe multi-tenancy for dev/staging. Production isolation prevents dev/staging changes from impacting production stability.

**Requirements**:
- Development apps MUST target `dev-vcluster` destination
- Staging apps MUST target `staging-vcluster` destination
- Production apps MUST target dedicated cluster or isolated namespace with NetworkPolicies
- Environment-specific configuration MUST use parameterized chart props (e.g., `environmentName`, `replicas`)
- Cross-environment promotion MUST use Kargo pipelines with explicit approval gates

**Enforcement**:
- ArgoCD Application `destination.name` MUST be validated against allowed environments
- VCluster manifests MUST be deployed before environment-specific applications (sync wave `-100`)
- Production RBAC MUST deny access to dev/staging namespaces

### IV. Declarative Configuration

All application configuration, secrets references, and infrastructure resources MUST be declared in code. No manual configuration or imperative scripts except for initial cluster bootstrapping.

**Rationale**: Declarative configuration is self-documenting, version-controlled, and reproducible. It eliminates configuration drift and "works on my machine" issues. All changes are auditable through Git history.

**Requirements**:
- Application config MUST use `config/applications.ts` declarative format
- **Unified Application Config**: Single `applications.ts` file MUST contain all applications for all cluster types
- Application configs MUST include `clusterType: 'kind' | 'talos' | 'both'` field
- Synthesis MUST filter applications based on `clusterType` field and current `CLUSTER_TYPE` environment variable
- Chart types MUST be registered in `IdpBuilderChartFactory`
- Secrets MUST use External Secrets Operator (ESO) with `ExternalSecret` CRDs
- Infrastructure resources MUST be defined in `cdk8s/charts/infra/`
- No environment variables or ConfigMaps created outside of CDK8s synthesis

**Enforcement**:
- Code reviews MUST reject manual `kubectl` commands in documentation or scripts
- CI MUST verify all applications exist in `config/applications.ts`
- Secrets scanning MUST prevent hardcoded secrets in Git
- Code reviews MUST reject separate application config files per cluster type

### V. CNOE Technology Alignment

Platform technology choices MUST align with CNOE (Cloud Native Operational Excellence) endorsed technologies for internal developer platforms.

**Rationale**: CNOE provides de-risked, community-validated technology choices for platform engineering. Following CNOE standards enables knowledge sharing, contribution coordination, and long-term supportability.

**Required Technologies**:
- **Code Repository**: Git (Gitea for local, GitHub for external)
- **Artifact Registry**: OCI registries (Gitea OCI for local, GHCR for external)
- **Continuous Delivery**: Argo CD
- **Workflow Orchestration**: Argo Workflows
- **Identity & Access**: Keycloak
- **Developer Portal**: Backstage
- **Secret Management**: External Secrets Operator
- **Packaging & Templating**: cdk8s (TypeScript)
- **Deployment Orchestration**: Kargo
- **Compute Platform**: Kubernetes (kind for local, EKS/AKS for cloud, Talos for bare-metal)

**Platform Capabilities** (CNOE-aligned extensions):
- **Remote Access**: Tailscale for secure cluster access (with authentication, impersonation, HA)
- **UI/Dashboard**: Headlamp for Kubernetes cluster management
- **AI/Automation**: kagent for AI-augmented operations, kmcp for MCP server management

**Enforcement**:
- Technology proposals MUST justify deviations from CNOE stack
- New platform capabilities MUST use CNOE-endorsed tools when available
- Deprecated tools (e.g., Helm, Terraform for K8s resources) MUST be migrated to CNOE equivalents

### VI. Package-Based Architecture

All applications and platform services MUST be organized as self-contained packages with manifests, kustomization.yaml, and ArgoCD Application definitions.

**Rationale**: Package-based architecture enables modular deployment, independent versioning, and clear dependency management. IdpBuilder's `cnoe://` URL syntax requires this structure for local development workflow.

**Requirements**:
- Each application MUST synthesize to `cdk8s/dist/<app>/manifests/` directory
- Each package MUST include `kustomization.yaml` (generated by `KustomizationGenerator`)
- Each package MUST have corresponding `cdk8s/dist/<app>.yaml` ArgoCD Application
- Chart classes MUST be organized by domain:
  - `cdk8s/charts/apps/`: Application workloads
  - `cdk8s/charts/platform/`: Platform services
  - `cdk8s/charts/pipelines/`: Kargo pipelines
  - `cdk8s/charts/secrets/`: External Secrets
  - `cdk8s/charts/infra/`: Infrastructure components
- Shared logic MUST be extracted to `cdk8s/lib/` helpers

**Enforcement**:
- Synthesis MUST fail if package structure is invalid
- CI MUST verify kustomization.yaml exists and references all manifests
- Package deployments MUST be independent (no inter-package file dependencies)

### VII. Security by Default

All workloads MUST implement security best practices: External Secrets for sensitive data, SecurityContext for pods, resource limits, mTLS where applicable, and NetworkPolicies.

**Rationale**: Security vulnerabilities in platform services can compromise entire infrastructure. Default-secure patterns prevent accidental exposure and reduce attack surface.

**Requirements**:
- Secrets MUST use External Secrets Operator (ESO) with Azure Key Vault or approved secret stores
- Pods MUST define `securityContext`:
  - `runAsNonRoot: true`
  - `allowPrivilegeEscalation: false`
  - `readOnlyRootFilesystem: true` (where feasible)
- Containers MUST define resource limits and requests
- Production namespaces SHOULD define NetworkPolicies for ingress/egress control
- ServiceAccounts MUST follow principle of least privilege (explicit RBAC bindings)
- TLS certificates MUST be managed via cert-manager or ESO

**mTLS & Certificate Management**:
- Talos API access MUST use mTLS certificates from cluster secrets
- Kubernetes API access MUST use kubeconfig with short-lived tokens where possible
- Certificate rotation schedule:
  - Talos certificates: Rotate annually or on suspected compromise
  - Kubernetes certificates: Auto-rotated by Talos
  - mTLS client certificates: Rotate quarterly for automation accounts

**Secrets Encryption Patterns**:
- **KIND (Local Dev)**: ESO with Azure Key Vault
- **Talos (Production)**: SOPS with age encryption for GitOps secrets, ESO for runtime secrets

**SOPS Configuration** (for Talos clusters):
```yaml
# .sops.yaml
creation_rules:
  - path_regex: secrets/.*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Enforcement**:
- OPA Gatekeeper policies MUST reject pods without `securityContext`
- OPA policies MUST reject pods without resource limits in production
- Code reviews MUST verify ESO usage for all secrets
- Secret scanning MUST prevent hardcoded secrets in manifests
- Talos API endpoints MUST be firewalled to trusted networks only (Tailscale)

### VIII. AI-Augmented Platform Engineering

Platform operations and developer workflows MAY leverage AI agents for automation, observability, and operational excellence when human judgment is augmented (not replaced).

**Rationale**: AI agents can accelerate platform operations by automating repetitive tasks, providing intelligent recommendations, and enabling natural language interfaces to Kubernetes infrastructure. However, critical decisions and production changes MUST remain under human control with proper approval gates.

**Permitted Use Cases**:
- **Observability**: AI agents analyzing logs, metrics, and events to surface insights
- **Troubleshooting**: Automated diagnosis of common issues with human-reviewed remediation
- **Documentation**: AI-generated runbooks, architecture diagrams, and developer guides
- **Policy Compliance**: AI-assisted validation of security policies and best practices
- **Developer Self-Service**: Natural language interfaces to Backstage, Kubernetes APIs

**Prohibited Use Cases**:
- Autonomous production deployments without human approval
- AI-generated code changes committed directly to main branches
- Unsupervised deletion or modification of critical infrastructure
- AI decisions overriding human-defined security policies

**Requirements**:
- AI agents MUST operate in isolated namespaces with least-privilege RBAC
- AI agent actions MUST be logged and auditable
- Production changes suggested by AI MUST require human approval
- AI models MUST be versioned and their configurations stored in Git
- LLM API keys MUST be stored in External Secrets Operator (Azure Key Vault)

**Implementation (kagent/kmcp)**:
- **kagent-controller**: Manages Agent, ModelConfig, RemoteMCPServer CRDs; provides HTTP API
- **kagent-dashboard**: Next.js UI for agent management and monitoring
- **kmcp-controller**: Manages MCPServer CRDs, deploys MCP server instances
- **kagent-secrets**: ExternalSecrets syncing LLM API keys (Anthropic, OpenAI, Gemini)
- **Access**: Dashboard at `https://kagent.cnoe.localtest.me:8443` (domain-based routing)

**Enforcement**:
- AI agents MUST NOT have cluster-admin privileges
- Production namespace RBAC MUST deny AI agent write access without approval workflows
- AI agent configurations MUST be code-reviewed before deployment
- Known upstream bugs (e.g., kagent v0.6.3 controller crashes) MUST be documented

### IX. Unified Cluster Bootstrap

Bootstrap and synthesis workflows MUST be consolidated across cluster types (KIND, Talos) using environment-driven configuration, not separate scripts or entry points.

**Rationale**: Maintaining separate bootstrap workflows for each cluster type creates duplication, inconsistency, and maintenance burden. A unified approach with environment-driven branching reduces code, ensures consistency, and simplifies onboarding.

**Requirements**:
- **Single Synthesis Entry Point**: `cdk8s/main.ts` MUST be the only synthesis entry point
- **Environment Variables**:
  - `CLUSTER_TYPE`: MUST be set to `kind` or `talos` before synthesis
  - `GIT_REPO_URL`: Required for Talos (GitHub repository URL)
  - `GIT_BRANCH`: Optional, defaults to `main`
- **Environment Files**:
  - `.env-files/kind.env`: KIND-specific configuration with `CLUSTER_TYPE=kind`
  - `.env-files/talos.env`: Talos-specific configuration with `CLUSTER_TYPE=talos`
- **Application Filtering**: Synthesis MUST only include applications where `clusterType` matches current `CLUSTER_TYPE` or is `'both'`
- **Source URL Utility**: `cdk8s/lib/source-url.ts` MUST provide centralized logic for ArgoCD source URL generation
- **Orchestrator Separation**: Deployment orchestrators remain cluster-specific:
  - KIND: `deployment/scripts/cluster-menu.sh` using idpBuilder
  - Talos: `scripts/bootstrap-cluster.sh` using Helm and kubectl
- **Legacy Script Handling**: Old scripts (`wi-kind.sh`, `wi-kind-lib.sh`) MUST display deprecation warnings

**Talosctl Command Reference** (for Talos clusters):
| Command | Purpose |
|---------|---------|
| `talosctl apply-config` | Apply machine configuration |
| `talosctl upgrade` | Upgrade Talos OS version |
| `talosctl dashboard` | Interactive TUI for node monitoring |
| `talosctl logs` | View service logs |
| `talosctl health` | Check cluster health |
| `talosctl etcd snapshot` | Create etcd backup |
| `talosctl bootstrap --recover-from` | Restore from etcd snapshot |

**Enforcement**:
- Code reviews MUST reject separate `main-*.ts` files per cluster type
- Code reviews MUST reject separate `*-applications.ts` files per cluster type
- CI MUST verify synthesis succeeds with both `CLUSTER_TYPE=kind` and `CLUSTER_TYPE=talos`
- Documentation MUST reference unified synthesis, not cluster-specific entry points

### X. Immutable Infrastructure for Talos

Talos clusters MUST be managed as immutable, API-driven infrastructure with no shell access.

**Rationale**: Talos Linux eliminates the attack surface of traditional Linux distributions by removing shells, package managers, and SSH. The API-only approach ensures all operations are auditable, reproducible, and secure.

**Requirements** (Talos clusters only):
- System management MUST be performed exclusively via `talosctl` API
- No SSH access is permitted - Talos has no SSH daemon by design
- Machine configuration MUST be applied atomically via `talosctl apply-config`
- OS updates MUST use Talos's image-based upgrade mechanism
- Configuration drift is impossible - the system always matches the declared state
- Debug access MUST use `talosctl dashboard` or `talosctl logs`

**Config Generation Pattern**:
```bash
talosctl gen config cluster-name https://<LB_IP>:6443 \
  --with-secrets secrets/secrets.yaml \
  --config-patch @patches/common.yaml \
  --config-patch-control-plane @patches/controlplane/all.yaml \
  --config-patch-worker @patches/worker/all.yaml
```

**Enforcement**:
- Direct `talosctl apply-config` without Git commit is FORBIDDEN in production
- Machine configs MUST be regenerated from source files, never edited directly
- Config validation MUST pass before any apply: `talosctl validate`

### XI. High Availability & Disaster Recovery

Production clusters MUST be highly available with proper redundancy, backup, and recovery procedures.

**Rationale**: High availability ensures the cluster survives node failures without downtime. Automated backups enable disaster recovery and compliance requirements.

**Requirements**:
- Control plane MUST have exactly 3 nodes for etcd quorum (never 2 or even numbers)
- etcd MUST have automated snapshot backups every 6 hours minimum
- etcd snapshots MUST be stored off-cluster (Azure Blob, S3, object storage)
- Workloads MUST NOT run on control plane nodes in production
- Pod Disruption Budgets MUST be defined for all critical workloads
- Node failure MUST NOT cause data loss (replicated storage, PDBs)

**Backup Verification**:
- Backup restoration MUST be tested quarterly
- Recovery time objective (RTO) MUST be documented
- Recovery point objective (RPO) MUST be documented

**Enforcement**:
- etcd backup job MUST be monitored for failures
- Alerts MUST fire for: etcd quorum loss, backup failure, storage capacity warnings
- Disaster recovery runbook MUST be reviewed during incident response

### XII. Upgrade & Rollback Discipline

All upgrades MUST be planned, tested, and reversible. No unplanned production upgrades.

**Rationale**: Kubernetes and Talos upgrades can introduce breaking changes. Sequenced upgrades with dry-runs minimize risk, and documented rollback procedures ensure recovery from failed upgrades.

**Requirements**:
- Pre-upgrade checklist MUST be completed before any upgrade
- Dry-run MUST be performed where available
- Backups MUST be verified before upgrades
- Rollback procedure MUST be documented and tested
- Maintenance windows MUST be communicated to stakeholders

**Talos Upgrade Sequence**:
1. Create fresh etcd snapshot
2. Verify cluster health: `talosctl health`
3. Upgrade workers one-by-one with drain
4. Upgrade control plane one-by-one (never all at once)
5. Verify cluster health after each node

**KIND Upgrade Sequence**:
1. Run `cluster-synth` to verify manifests
2. Run `cluster-update` for incremental changes
3. Run `cluster-recreate` only for breaking changes
4. Verify ArgoCD sync status

**Enforcement**:
- Production upgrades MUST go through change management process
- Rollback documentation MUST be updated after each upgrade procedure change
- Failed upgrades MUST trigger incident response

### XIII. Observability & Monitoring

Cluster health MUST be continuously monitored with alerting for anomalies.

**Rationale**: You can't fix what you can't see. Comprehensive monitoring enables proactive issue resolution, capacity planning, and incident response.

**Requirements**:
- Prometheus MUST collect metrics from all nodes and workloads
- Grafana MUST provide dashboards for cluster health visualization
- Alertmanager MUST route alerts to appropriate channels
- Logs MUST be collected centrally (Loki, cloud provider)
- SLOs MUST be defined for cluster availability (target: 99.9%)

**Critical Alerts**:
- Node unreachable for >5 minutes
- etcd quorum at risk (<2 healthy members)
- Certificates expiring within 30 days
- API server latency >1s (P99)
- Resource utilization >90% sustained

**Dashboards MUST include**:
- Node health and resource utilization
- etcd health and latency
- API server request latency
- ArgoCD sync status
- External Secrets sync status

**Enforcement**:
- Monitoring stack MUST be deployed via GitOps
- Alert rules MUST be version-controlled
- On-call rotation MUST be documented
- Incident response runbooks MUST reference dashboards

## Network Security & Tailscale

### Zero-Trust Network Architecture

Network access MUST follow zero-trust principles with Tailscale as the secure access layer.

**Requirements**:
- Tailscale MUST be the primary access method for cluster management (Talos API, K8s API, ArgoCD UI)
- Public internet exposure of management APIs is FORBIDDEN
- Network policies MUST default-deny with explicit allow rules

**Tailscale Integration Modes**:
1. **Operator Mode**: Deploy Tailscale Kubernetes Operator for service exposure
2. **Subnet Router Mode**: Expose cluster network to tailnet
3. **Service Exposure Mode**: Expose specific services via LoadBalancer

**Tailscale ACL Pattern**:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:k8s-admins"],
      "dst": ["tag:k8s-api:6443", "tag:talos-api:50000", "tag:argocd:443"]
    },
    {
      "action": "accept",
      "src": ["group:developers"],
      "dst": ["tag:argocd:443"]
    }
  ]
}
```

**Access Patterns**:
| Resource | Access Method | Authentication |
|----------|---------------|----------------|
| Talos API | Tailscale → node IP:50000 | mTLS (talosconfig) |
| K8s API | Tailscale → node IP:6443 | kubeconfig (certificates) |
| ArgoCD UI | Tailscale service | SSO or admin password |

## Development Standards

### Chart Development

- Chart classes MUST define typed interfaces extending `ChartProps` for all constructor parameters
- Complex charts MUST include JSDoc comments explaining purpose and usage
- Chart props MUST be validated (throw errors for invalid configurations)
- Charts MUST be registered in `IdpBuilderChartFactory` before use
- Chart names MUST match class names (e.g., `BackstageChart` → `'BackstageChart'`)

### Synthesis Workflow

1. Set `CLUSTER_TYPE` environment variable (or source appropriate `.env-files/*.env`)
2. Edit chart code in `cdk8s/charts/`
3. Update `config/applications.ts` if adding/removing applications (include `clusterType` field)
4. Run `npm run synth` to synthesize all packages for current cluster type
5. Verify output in `cdk8s/dist/<app>/manifests/`
6. Deploy via appropriate orchestrator:
   - KIND: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
   - Talos: `./scripts/bootstrap-cluster.sh`
7. Validate in ArgoCD UI and `kubectl get all -n <namespace>`

### ArgoCD CLI Usage

When using `argocd` CLI for local development:

```bash
# Source cluster management functions (sets ARGOCD_AUTH_TOKEN)
source ~/stacks/deployment/scripts/cluster-menu.sh

# Always add --insecure flag for local dev (self-signed certs)
argocd app list --insecure
argocd app get argocd/backstage --insecure
argocd app sync argocd/my-app --prune --insecure

# Or use helper functions (--insecure added automatically)
argocd-status              # Show formatted application status
argocd-sync argocd/my-app  # Sync specific application
argocd-list-outofsync      # List out-of-sync applications
```

### Testing Requirements

- **Type Checking**: MUST pass `npm run compile` before synthesis
- **Dry-Run Validation**: SHOULD run `kubectl diff -f dist/<app>/manifests/` against target cluster
- **Local Testing**: MUST test in local kind cluster before production deployment
- **Integration Testing**: SHOULD verify ArgoCD sync succeeds without errors
- **Regression Testing**: MUST verify existing applications remain healthy after changes
- **Cross-Cluster Validation**: MUST verify synthesis produces valid output for both `CLUSTER_TYPE=kind` and `CLUSTER_TYPE=talos`

## Quality & Testing Requirements

### Mandatory Quality Gates

1. **TypeScript Compilation**: All code MUST compile without errors or warnings
2. **Synthesis**: All charts MUST synthesize without errors
3. **Manifest Validation**: Generated YAML MUST be valid Kubernetes resources
4. **ArgoCD Application**: All applications MUST have valid ArgoCD Application manifests
5. **Sync Wave Ordering**: Dependencies MUST be declared via sync waves or explicit dependencies
6. **Cluster Type Coverage**: Synthesis MUST succeed for all supported cluster types

### Optional Testing (Required for Complex Features)

- **Contract Testing**: API endpoints and service interfaces
- **Integration Testing**: Multi-component workflows (ArgoCD + Kargo, ESO + Azure Key Vault)
- **End-to-End Testing**: Full user journeys in Backstage templates

### Documentation Requirements

- Complex charts MUST include inline comments explaining logic
- Chart props MUST be documented via TypeScript interfaces
- Breaking changes MUST be documented in CHANGELOG.md
- Architecture decisions MUST be captured in `docs/` directory or ADRs
- Runbooks MUST exist for: upgrades, backup/restore, scaling, incident response

## Governance

### Amendment Process

1. Proposed changes MUST be documented in a pull request
2. Amendments MUST include:
   - Rationale for change
   - Impact analysis on existing principles
   - Migration plan for affected code
   - Version bump justification (MAJOR/MINOR/PATCH)
3. Amendments MUST be reviewed and approved by project maintainers
4. Version MUST be incremented according to semantic versioning:
   - **MAJOR**: Backward incompatible governance/principle removals or redefinitions
   - **MINOR**: New principle/section added or materially expanded guidance
   - **PATCH**: Clarifications, wording, typo fixes, non-semantic refinements

### Compliance Review

- All pull requests MUST verify compliance with constitution principles
- CI/CD pipeline MUST enforce type checking, synthesis validation, and security policies
- Quarterly reviews SHOULD assess adherence and identify improvement areas
- Violations MUST be documented and justified or remediated

### Compliance Checklist

All changes MUST verify compliance with:
- ✅ Type-safe infrastructure - TypeScript CDK8s, single main.ts
- ✅ GitOps deployment - ArgoCD, no manual kubectl in production
- ✅ Declarative configuration - All config in Git, unified applications.ts
- ✅ Security by default - ESO, SecurityContext, mTLS, certificate rotation
- ✅ Package-based architecture - Modular packages, kustomization.yaml
- ✅ Unified bootstrap - CLUSTER_TYPE environment variable, shared synthesis
- ✅ Immutable infrastructure (Talos) - API-only operations, no SSH
- ✅ High availability - 3 CP nodes, etcd backups, tested restore
- ✅ Upgrade discipline - Sequenced, tested, documented rollback
- ✅ Observability - Prometheus/Grafana, critical alerts configured
- ✅ Network security - Tailscale, zero-trust, default-deny policies
- ✅ AI governance - Human approval for production changes

### Complexity Justification

Any deviation from constitution principles (e.g., using Helm for third-party charts, imperative scripts for bootstrapping) MUST be justified in writing with:
- Why the deviation is necessary
- What simpler alternatives were considered and rejected
- Plan to align with constitution when feasible

### Runtime Development Guidance

For day-to-day development guidance, refer to `CLAUDE.md` which provides:
- Common commands and workflows
- Code organization patterns
- Troubleshooting procedures
- Best practices and examples

This constitution supersedes `CLAUDE.md` when principles conflict. `CLAUDE.md` provides implementation details; the constitution provides non-negotiable rules.

**Version**: 1.3.0 | **Ratified**: 2025-10-08 | **Last Amended**: 2025-12-07
