# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitOps infrastructure repository using CDK8s (TypeScript) to define Kubernetes manifests, deployed via IdpBuilder and managed by ArgoCD. The stack includes platform services like Backstage, Keycloak, External Secrets Operator, Kargo pipelines, and multi-environment VClusters.

### What is CNOE?

CNOE (Cloud Native Operational Excellence, pronounced "Kuh.noo") brings together enterprises to navigate operational technology decisions, de-risk tooling bets, and provide guidance on which CNCF technologies to use together for cloud efficiencies. Key principles:

- **Open source first:** Prioritize open source over proprietary technology
- **Community driven:** Decisions driven by community and governing body
- **Tools and not Practices:** Offers suggestions on which tools to use and configurations
- **Powered by Kubernetes:** Uses Kubernetes as the de-facto operating environment
- **Standardized to infrastructure, customizable by developers:** Balance between enforcement and usability

### What is cdk8s?

cdk8s is a software development framework for defining Kubernetes applications using familiar programming languages and rich object-oriented APIs. Key concepts:

- **App → Charts → Constructs → Resources:** Apps contain Charts (synthesized to separate manifests), Charts contain Constructs, Constructs represent Kubernetes resources
- **Pure YAML generation:** cdk8s generates standard Kubernetes YAML that can be applied via `kubectl` or GitOps tools
- **Language native:** Full TypeScript type system, IDE support, testing capabilities
- **No runtime component:** Only generates manifests, doesn't apply them

### What is idpBuilder?

idpBuilder simplifies spinning up a complete internal developer platform (IDP) on local machines with only Docker as dependency. When you run `idpbuilder create`:

1. Creates local kind cluster (if needed)
2. Installs core packages: ArgoCD (GitOps), Gitea (in-cluster Git server + OCI registry), ingress-nginx
3. Configures self-signed certificate and CoreDNS for name resolution
4. Passes control to ArgoCD by storing manifests in Gitea repositories

**Key Features:**
- **cnoe:// URL syntax:** Special protocol for local packages (see below)
- **Local OCI registry:** Built-in container registry in Gitea
- **Two routing modes:** Domain-based (default) or path-based (for Codespaces)
- **GitOps workflow:** Gitea allows anonymous read access; no pull secrets needed

## Common Commands

### CDK8s Development

```bash
# From the cdk8s/ directory:
cd cdk8s

# Install dependencies
npm install

# Synthesize all packages (generates dist/)
npx ts-node main-v2.ts

# Type check
npm run compile
# or
npx tsc --noEmit

# Import/update CRDs
npm run import

# Watch mode (auto-synthesize on file changes)
npm run watch:synth
```

### IdpBuilder Deployment

```bash
# Deploy all synthesized packages
idpbuilder create --package cdk8s/dist/

# Deploy specific package
idpbuilder create --package cdk8s/dist/<app-name>

# Deploy with path-based routing (for Codespaces or single domain)
idpbuilder create --use-path-routing --package cdk8s/dist/

# Get secrets (e.g., Gitea token)
idpbuilder get secrets
idpbuilder get secrets -p gitea
idpbuilder get secrets -p gitea -o json | jq -r '.[0].data.token'

# Get cluster info
idpbuilder get clusters

# Delete cluster
idpbuilder delete --name localdev
```

### Working with Local OCI Registry

```bash
# Login to Gitea registry
idpbuilder get secrets -p gitea -o json | jq '.[0].password' -r | \
  docker login -u giteaAdmin --password-stdin gitea.cnoe.localtest.me:8443

# Push image to local registry
docker pull ubuntu:24.04
docker tag ubuntu:24.04 gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04
docker push gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04

# Pull image from local registry (no auth needed for pulls)
docker pull gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04
```

**Note:** Gitea OCI registry allows anonymous read access. Image naming convention: `{registry}/{owner}/{image}`

### ArgoCD CLI

```bash
# Source cluster management functions (sets ARGOCD_AUTH_TOKEN automatically)
source ~/stacks/deployment/scripts/cluster-menu.sh

# Use native argocd CLI - always add --insecure flag for local dev
argocd app list --insecure
argocd app get argocd/backstage --insecure
argocd app sync argocd/my-app --prune --insecure

# Or use helper functions (--insecure added automatically)
argocd-status              # Show formatted application status
argocd-sync argocd/my-app  # Sync specific application
argocd-list-outofsync      # List out-of-sync applications
```

**Required Flag:** Always use `--insecure` for local development (self-signed certificates)
**Authentication:** Automatic via `ARGOCD_AUTH_TOKEN` environment variable (set by cluster-menu.sh)
**Documentation:** See `deployment/docs/ARGOCD_AUTOMATION.md` for details

### Testing

```bash
# Dry-run/validation
cd cdk8s
npm run synth
kubectl diff -f dist/<app>/manifests/

# Local testing with Kind
kind create cluster --name test
kubectl apply -f dist/<app>/manifests/
kubectl get all -n <namespace>
```

### Nix Binary Cache (Attic + MinIO)

**Purpose**: In-cluster Nix binary cache for accelerating NixOS VM builds (20-25 min → under 3 min)

```bash
# Deploy MinIO + Attic (via cluster-update)
source deployment/scripts/cluster-menu.sh
cluster-update  # Deploys all packages including nix-cache

# Check deployment status
kubectl get pods -n nix-cache
# Expected: minio-xxx (Running), attic-xxx (Running)

# Initialize cache (generates admin token, creates "nixos" cache namespace)
./deployment/scripts/nix-cache/init-attic-cache.sh
# Save the admin token and NixOS configuration snippet displayed

# Push packages from Hetzner host (requires Attic CLI and port-forward/Tailscale)
./deployment/scripts/nix-cache/push-to-cache.sh /run/current-system

# Verify cache contents
kubectl port-forward -n nix-cache svc/attic 8080:8080 &
curl http://localhost:8080/nixos/nix-cache-info
# Expected: HTTP/1.1 200 OK
```

**Key Files**:
- Charts: `cdk8s/charts/infra/nix-cache-namespace-chart.ts`, `minio-chart.ts`, `attic-chart.ts`
- Scripts: `deployment/scripts/nix-cache/init-attic-cache.sh`, `push-to-cache.sh`
- Docs: `specs/003-implement-attic-minio/quickstart.md` (complete deployment guide)

**Architecture**:
- **MinIO**: S3-compatible object storage (100Gi PVC, sync wave -100)
- **Attic**: Nix binary cache server (sync wave -90, depends on MinIO)
- **Cache Namespace**: Logical grouping ("nixos") with unique signing key for package verification

**Troubleshooting**:
- MinIO CrashLoopBackOff: Check disk space (`docker exec kind-control-plane df -h`)
- Attic connection errors: Verify MinIO is Running (`kubectl get pods -n nix-cache -l app=minio`)
- Cache push 401: Regenerate admin token via init-attic-cache.sh
- VM can't reach cache: Check DNS resolution from VM (`curl http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`)

For full documentation, see `specs/003-implement-attic-minio/quickstart.md`.

### kagent/kmcp (AI Agent Platform)

```bash
# Synthesis
cd cdk8s
npx ts-node main-v2.ts  # Synthesizes kagent, kmcp, kagent-secrets, kagent-agents packages

# Deployment (use cluster-menu.sh wrapper - see constitution)
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update  # Deploys all packages including kagent

# Check pod status
kubectl get pods -n kagent
# Expected: kagent-controller, kagent-dashboard, kagent-tools, kmcp-controller, mcp-website-fetcher

# Check custom resources
kubectl get agents,modelconfigs,mcpservers,remotemcpservers -n kagent

# Access dashboard (via ingress - domain-based routing)
# Open https://kagent.cnoe.localtest.me:8443
# Or via port-forward: kubectl port-forward -n kagent svc/kagent-dashboard 8082:8082 then http://localhost:8082

# Test controller API
kubectl port-forward -n kagent svc/kagent-controller 8083:8083
curl http://localhost:8083/api/v1/agents  # List agents

# Check ArgoCD applications
argocd app list --insecure | grep kagent
# Expected: kagent, kmcp, kagent-secrets, kagent-agents all Synced/Healthy

# Troubleshooting
kubectl logs -n kagent deploy/kagent-controller --tail=50  # Controller logs
kubectl logs -n kagent deploy/kmcp-controller --tail=50    # kmcp logs
kubectl describe agent -n kagent <agent-name>              # Agent status
kubectl describe mcpserver -n kagent <server-name>         # MCP server status

# Common issues:
# - Agents not ready: Check modelconfig exists and API keys in kagent-llm-providers secret
# - MCP server not ready: Check kmcp-controller has ServiceAccount permissions
# - Dashboard ingress: Access via https://kagent.cnoe.localtest.me:8443 (domain-based routing)
# - Controller errors: Ensure RBAC includes configmaps, secrets, deployments, agents CRDs

# KNOWN ISSUE (kagent v0.6.3):
# The kagent-controller has upstream bugs causing nil pointer dereferences during initialization:
#   - findAgentsUsingMCPService (line 261): crashes when indexing MCP servers
#   - findAgentsUsingModelConfig (line 302): crashes when indexing model configs
# The controller enters CrashLoopBackOff on startup even with empty cluster (no resources).
# Workaround: Use kagent-dashboard directly (works without controller) or wait for upstream fix.
# Dashboard remains fully functional at https://kagent.cnoe.localtest.me:8443
```

**kagent Architecture**:
- **kagent-controller**: Manages Agent, ModelConfig, RemoteMCPServer CRDs; runs HTTP API on port 8083
- **kagent-dashboard**: Next.js UI for agent management (port 8080)
- **kagent-tools**: Built-in Kubernetes tools MCP server (RemoteMCPServer)
- **kmcp-controller**: Manages MCPServer CRDs, creates deployments for MCP servers
- **kagent-secrets**: External Secrets syncing LLM API keys from Azure Key Vault (ANTHROPIC-API-KEY, OPENAI-API-KEY, GEMINI-API-KEY)

**Access URLs**:
- **kagent Dashboard**: https://kagent.cnoe.localtest.me:8443 (domain-based routing)
- **ArgoCD Applications**:
  - kagent platform: https://argocd.cnoe.localtest.me:8443/applications/kagent
  - kmcp controller: https://argocd.cnoe.localtest.me:8443/applications/kmcp
  - kagent secrets: https://argocd.cnoe.localtest.me:8443/applications/kagent-secrets
  - kagent agents: https://argocd.cnoe.localtest.me:8443/applications/kagent-agents

## Architecture

### Code Organization

**Main Entry Point:**
- `cdk8s/main-v2.ts`: Loads `config/applications.ts`, uses `IdpBuilderChartFactory` to create charts, synthesizes per-app packages to `cdk8s/dist/<app>/manifests`, writes kustomization.yaml, emits `cdk8s/dist/<app>.yaml` ArgoCD Application manifests.

**Configuration:**
- `cdk8s/config/applications.ts`: Declarative `ApplicationConfig[]` driving chart type, namespace, sync wave, labels/annotations, dependencies.

**Charts by Domain:**
- `cdk8s/charts/apps/`: Application workloads (Next.js, Postgres, Redis)
- `cdk8s/charts/platform/`: Platform apps (ArgoCD Application builders, Headlamp, Namespaces)
- `cdk8s/charts/pipelines/`: Kargo pipeline resources (Projects, Warehouses, Stages, RBAC)
- `cdk8s/charts/secrets/`: External Secrets definitions and Workload Identity patches
- `cdk8s/charts/infra/`: Infrastructure charts (Dagger, Vault)

**Shared Libraries:**
- `cdk8s/lib/idpbuilder-chart-factory.ts`: Registers/creates chart instances by name
- `cdk8s/lib/argocd-sync-builders.ts`: Sync-wave, hook, and Argo-specific annotations helpers
- `cdk8s/lib/eso-helpers.ts`: Reusable builders for ExternalSecret patterns (env secrets, dockerconfigjson, TLS)
- `cdk8s/lib/kargo-rbac.ts`: Helper for Kargo pipeline ServiceAccount + RoleBinding
- `cdk8s/lib/auto-register-charts.ts`: Auto-registration of chart classes
- `cdk8s/lib/kustomization-generator.ts`: Generates kustomization.yaml for packages

**Typed Imports:**
- `cdk8s/imports/k8s.ts`: Kubernetes core types (KubeDeployment, KubeService, KubeIngress, etc.)
- `cdk8s/imports/argoproj.io.ts`: Argo resources (Application, WorkflowTemplate, etc.)
- `cdk8s/imports/external-secrets.io.ts`: External Secrets CRDs
- `cdk8s/imports/kargo.akuity.io.ts`: Kargo CRDs

**Other Directories:**
- `ref-implementation/`: CNOE reference implementation with example packages
- `deployment/`: Deployment configurations
- `scripts/`: Utility scripts (cluster setup, certificate management)
- `docs/`: Comprehensive documentation (architecture, workflow, troubleshooting)

### CDK8s Pattern: Typed TypeScript over YAML Templating

We use CDK8s with TypeScript to solve YAML templating issues (Helm, Kustomize):
- **Type Safety:** Compile-time validation of Kubernetes resources
- **IDE Support:** Full autocomplete, refactoring, error detection
- **Reusability:** Shared functions and classes
- **Complex Logic:** Full programming language capabilities

**Resource Definition Approaches:**

1. **Low-level API (imports/k8s):** For exact YAML control
   ```typescript
   import * as k8s from './imports/k8s';

   new k8s.KubeDeployment(this, 'my-deployment', {
     spec: {
       replicas: 3,
       selector: { matchLabels: { app: 'my-app' } },
       template: {
         metadata: { labels: { app: 'my-app' } },
         spec: {
           containers: [{
             name: 'app-container',
             image: 'nginx:1.19.10',
             ports: [{ containerPort: 80 }]
           }]
         }
       }
     }
   });
   ```

2. **High-level API (cdk8s-plus-32):** For ergonomics and reduced complexity
   ```typescript
   import * as kplus from 'cdk8s-plus-32';

   const deployment = new kplus.Deployment(this, 'Deployment', {
     replicas: 3,
     containers: [{ image: 'nginx:1.19.10', port: 80 }]
   });

   deployment.exposeViaService({
     serviceType: kplus.ServiceType.LOAD_BALANCER
   });
   ```

**When to use each:**
- **imports/k8s:** When you need exact YAML output, working with CRDs, or precise control over resource specifications
- **cdk8s-plus-32:** When defining standard Kubernetes resources (Deployments, Services, ConfigMaps) and ergonomics improve productivity without sacrificing clarity

**Note:** This repository primarily uses `imports/k8s` for consistency and exact YAML control. Use `cdk8s-plus-32` selectively when it improves ergonomics without altering YAML semantics.

### IdpBuilder Packages & cnoe:// URL Syntax

Synthesis produces IdpBuilder-ready packages:
- `cdk8s/dist/<app>/manifests/`: All resource YAMLs (FILE_PER_RESOURCE mode) + `kustomization.yaml`
- `cdk8s/dist/<app>.yaml`: ArgoCD Application referencing `cnoe://<app>/manifests` for local dev

**How `cnoe://` works:**
1. `cnoe://<package>/manifests` in Application source indicates local package path
2. IdpBuilder creates Gitea repository: `idpbuilder-localdev-<package>-manifests`
3. Pushes `dist/<package>/manifests/` contents to Gitea
4. Rewrites Application source URL to Gitea URL
5. ArgoCD syncs from Gitea repository

### ArgoCD Applications Architecture

- **Single-source vs multi-source:**
  - Single-source: one `source` pointing to `cnoe://<package>/manifests` during local dev
  - Multi-source: `sources[]` when pulling from both Helm and local files
- **Destinations:**
  - Dev/Staging Apps target named vclusters (e.g., `dev-vcluster`, `staging-vcluster`)
  - Others target in-cluster `https://kubernetes.default.svc`
- **Sync waves:** Use `argocd.argoproj.io/sync-wave` annotations to control ordering (namespaces < secrets < apps)
- **Kargo integration:** Some apps include `kargo.akuity.io/authorized-stage` annotations

### Secrets Management

Uses External Secrets Operator (ESO) with Azure Key Vault:
- **ClusterSecretStore:** Points to Azure Key Vault via Workload Identity
- **ExternalSecret:** Per-namespace resources syncing specific secrets
- **Patterns:** Environment secrets, dockerconfigjson (GHCR), TLS certificates

Workload Identity for ESO is configured via charts in `cdk8s/charts/secrets/`.

## Adding New Applications

1. **Create Chart:**
   ```typescript
   // cdk8s/charts/apps/my-new-app-chart.ts
   import { Chart, ChartProps } from 'cdk8s';
   import { Construct } from 'constructs';
   import * as k8s from '../../imports/k8s';

   export class MyNewAppChart extends Chart {
     constructor(scope: Construct, id: string, props?: ChartProps) {
       super(scope, id, props);
       // Define resources...
     }
   }
   ```

2. **Register Chart:**
   ```typescript
   // cdk8s/main-v2.ts
   import { MyNewAppChart } from './charts/apps/my-new-app-chart';
   IdpBuilderChartFactory.register('MyNewAppChart', MyNewAppChart);
   ```

3. **Add to Configuration:**
   ```typescript
   // cdk8s/config/applications.ts
   {
     name: 'my-new-app',
     namespace: 'my-new-app',
     chart: {
       type: 'MyNewAppChart',
       props: { /* chart-specific properties */ }
     },
     argocd: {
       syncWave: '100',
       labels: { 'app.kubernetes.io/name': 'my-new-app' },
       syncPolicy: { automated: { prune: true, selfHeal: true } }
     }
   }
   ```

4. **Synthesize and Deploy:**
   ```bash
   cd cdk8s
   npx ts-node main-v2.ts
   idpbuilder create --package dist/my-new-app
   ```

## Multi-Environment Patterns

**Parameterized Charts:**
```typescript
export interface MyAppParameterizedChartProps extends ChartProps {
  environmentName: string;
  replicas?: number;
}

export class MyAppParameterizedChart extends Chart {
  constructor(scope: Construct, id: string, props: MyAppParameterizedChartProps) {
    super(scope, id, props);
    const envName = props.environmentName;
    const replicas = props.replicas || (envName === 'production' ? 3 : 1);
    // Environment-specific configuration...
  }
}
```

Generate separate applications per environment in `config/applications.ts`.

## Best Practices

1. **Type Safety:** Use interfaces for chart props, validate configurations
2. **Resource Naming:** `<app>-<env>-<resource>` pattern
3. **Dependencies:** Declare explicitly via sync waves or dependencies config
4. **Sync Waves:** Typical order:
   - `-110` to `-100`: Namespaces, CRDs
   - `-90` to `-80`: RBAC, ServiceAccounts
   - `-70` to `-50`: Secrets, ConfigMaps
   - `0` to `50`: Deployments, StatefulSets
   - `100+`: Applications, Ingresses
5. **Error Handling:** Graceful degradation, validation checks
6. **Security:** Use External Secrets for sensitive data, set SecurityContext, resource limits, NetworkPolicies
7. **Documentation:** Comment complex logic, document chart props

## Troubleshooting

### TypeScript Errors
```bash
rm -rf cdk8s/node_modules/.cache
cd cdk8s && npm run compile
```

### Synthesis Failures
```bash
cd cdk8s
rm -rf dist/
npx ts-node main-v2.ts
```

### Import Issues
```bash
cd cdk8s
npm run import
```

### CNOE URL Not Resolving
Ensure deployment is via IdpBuilder (not direct `kubectl apply`).

### Sync Out of Order
Check `argocd.argoproj.io/sync-wave` annotations.

## CNOE Technology Stack

This repository implements CNOE-endorsed technologies for internal developer platforms:

| Category | Tool(s) | Implementation |
|----------|---------|----------------|
| Code Repository | Git | Gitea (local), GitHub (external) |
| Artifact Registry | Container Registries | Gitea OCI registry (local), GHCR (external) |
| Secret Repository | External Secrets | Azure Key Vault via Workload Identity |
| Secret Management | External Secrets | ESO with ClusterSecretStore |
| Continuous Delivery | Argo CD | GitOps for all platform services |
| Workflow Orchestration | Argo Workflows | CI/CD pipelines, Spark jobs |
| Identity & Access | Keycloak | SSO for Backstage, Argo, other services |
| Developer Portal | Backstage | Software catalog, templates, self-service |
| Packaging & Templating | cdk8s | TypeScript-based K8s manifest generation |
| Deployment Orchestration | Kargo | Progressive delivery pipelines |

**Platform Capabilities:**
- **Compute Platform:** Kubernetes (kind for local, EKS/AKS for production)
- **Multi-tenancy:** VClusters for environment isolation (dev, staging)
- **Service Discovery:** Kubernetes DNS, ingress-nginx
- **Observability:** Integration points for Prometheus, Grafana (not included in base)
- **Validation:** ArgoCD admission control, External Secrets validation

## Documentation

See `docs/` directory for detailed information:
- `README.md`: Documentation index
- `cnoe-overview.md`: CNOE philosophy, technology capabilities, idpBuilder reference
- `cdk8s-typescript-docs.md`: CDK8s fundamentals, cdk8s+ usage, CLI commands
- `cdk8s-architecture-and-packaging.md`: CDK8s architecture, code organization, IdpBuilder packaging
- `development-workflow.md`: Development patterns, testing, deployment process
- `gitops-architecture-overview.md`: GitOps architecture, design decisions
- `secrets-management.md`: External Secrets Operator, Azure Key Vault integration
- `AZURE_WORKLOAD_IDENTITY.md`: Azure Workload Identity setup

## Reference Implementation

The `ref-implementation/` directory contains a CNOE reference implementation with:
- **Argo Workflows:** Workflow orchestration (CI/CD, Spark jobs)
- **Backstage:** Developer portal (software catalog, templates, self-service)
- **External Secrets:** Secrets management with Azure Key Vault integration
- **Keycloak:** Identity provider (SSO for all services)
- **Spark Operator:** Example data processing workload

### Installation

```bash
idpbuilder create --use-path-routing \
  --kind-config ref-implementation/kind-config.yaml \
  --package https://github.com/cnoe-io/stacks//ref-implementation
```

This takes ~6 minutes. Track progress at ArgoCD UI.

### Access UIs

**Default (domain-based routing):**
- Argo CD: https://argocd.cnoe.localtest.me:8443
- Argo Workflows: https://argo-workflows.cnoe.localtest.me:8443
- Backstage: https://cnoe.localtest.me:8443
- Gitea: https://gitea.cnoe.localtest.me:8443
- Keycloak: https://keycloak.cnoe.localtest.me:8443/admin/master/console/

**Path-based routing (with `--use-path-routing`):**
- Argo CD: https://cnoe.localtest.me:8443/argocd
- Argo Workflows: https://cnoe.localtest.me:8443/argo-workflows
- Backstage: https://cnoe.localtest.me:8443/
- Gitea: https://cnoe.localtest.me:8443/gitea
- Keycloak: https://cnoe.localtest.me:8443/keycloak/admin/master/console/

### Default Credentials

```bash
# Get all secrets
idpbuilder get secrets

# Backstage login: user1 (admin) or user2 (regular user)
# Password: USER_PASSWORD from secrets output

# Keycloak admin: cnoe-admin
# Password: KEYCLOAK_ADMIN_PASSWORD from secrets output
```

### Example Use Cases

1. **Basic Deployment:** Create simple nginx deployment via Backstage template
2. **Argo Workflows + Spark:** Deploy Spark job through workflow template
3. **App with Cloud Resources:** Create app with S3 bucket (requires Crossplane setup)

**What happens when you create via Backstage:**
1. Backstage creates Git repository in Gitea, pushes templated contents
2. Backstage creates ArgoCD Application pointing to Git repository
3. Backstage registers component in catalog (catalog-info.yaml)
4. ArgoCD deploys manifests to cluster
5. Backstage retrieves health status from ArgoCD API

### DNS Resolution

- **External:** `cnoe.localtest.me` and subdomains resolve to `127.0.0.1`
- **In-cluster:** CoreDNS rewrites to `ingress-nginx-controller.ingress-nginx.svc.cluster.local`
- **Traffic flow:** localhost:8443 → kind container:443 → ingress-nginx → service

### Running on Remote Host

**Option 1 (SSH port forwarding):**
```bash
# On server
idpbuilder create

# On local machine
ssh -L 8443:server:8443 -L 32222:server:32222 -L 36091:server:36091 user@server
```

**Option 2 (Change ingress host):**
```bash
idpbuilder create --host SERVER.DOMAIN.NAME --use-path-routing
```
