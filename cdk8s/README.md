# CDK8s GitOps Infrastructure

TypeScript-based Kubernetes manifest generation using CDK8s for CNOE-compliant Internal Developer Platform.

## Prerequisites

### Required Tools

1. **Node.js 20+**
   ```bash
   node --version  # Should be v20.x or higher
   ```

2. **Helm 3.x** (for Kargo Helm chart rendering)
   ```bash
   # Via Nix (recommended for this devcontainer)
   nix profile install nixpkgs#kubernetes-helm

   # Verify installation
   helm version
   ```

3. **Git** (for version control)

## Quick Start

### First-Time Setup

```bash
cd cdk8s

# Install dependencies
npm install

# Import CRDs and generate TypeScript types
npm run import

# Synthesize Kubernetes manifests
npm run synth
```

**Output:** Manifests generated in `dist/` directory, ready for IDPBuilder.

### Deploy to Local Cluster

```bash
# From repository root
idpbuilder create --package cdk8s/dist/

# Or deploy specific application
idpbuilder create --package cdk8s/dist/kagent
```

## Architecture

### CRD Management

CRDs are **vendored** in `crds/` directory to ensure repo is fully self-contained:

- **`crds/external-secrets-crds.yaml`** - External Secrets Operator CRDs
- **`crds/tailscale-proxygroups-crd.yaml`** - Tailscale ProxyGroup CRD
- **`crds/kmcp-mcpserver-crd.yaml`** - kmcp MCPServer CRD
- **`crds/kgateway-placeholder.yaml`** - Placeholder (KGateway removed)

### Special Case: kagent CRDs

The `ai-platform-engineering` Helm chart (line 10 in `cdk8s.yaml`) **does not include CRDs**. Instead:

1. `imports/kagent.dev.ts` is **committed to the repository**
2. When running `npm run import`, this file is **preserved**
3. Do **NOT** regenerate this file manually

**Why?** The kagent controller CRDs are not distributed via Helm chart or public URLs. The types were generated from the source code and must be preserved.

### Chart Registration

Charts are **auto-registered** via `lib/auto-register-charts.ts`:

```typescript
// Scans charts/ directory and registers all chart classes
// No manual registration needed in main-v2.ts
```

## Development Workflow

### Adding New Applications

1. **Create Chart** in appropriate directory:
   ```
   cdk8s/charts/
   ├── apps/          # Application workloads
   ├── infra/         # Infrastructure (kagent, kmcp, dagger)
   ├── pipelines/     # Kargo pipelines
   ├── platform/      # Platform services (Headlamp, namespaces)
   └── secrets/       # External Secrets
   ```

2. **Add to Configuration** in `config/applications.ts`:
   ```typescript
   {
     name: 'my-app',
     namespace: 'my-app',
     chart: {
       type: 'MyAppChart',
       props: { /* ... */ }
     },
     argocd: {
       syncWave: '100',
       labels: { 'app.kubernetes.io/name': 'my-app' },
       syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
     }
   }
   ```

3. **Synthesize and Deploy:**
   ```bash
   npm run synth
   idpbuilder create --package dist/my-app
   ```

### Updating CRDs

When External Secrets, Tailscale, or kmcp release new versions:

```bash
# Update CRDs in crds/ directory
curl -sL https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml \
  -o crds/external-secrets-crds.yaml

# Regenerate TypeScript types
npm run import

# Commit updated CRDs
git add crds/ imports/
git commit -m "chore: update CRDs to vX.Y.Z"
```

**⚠️ IMPORTANT:** Do **NOT** regenerate `imports/kagent.dev.ts` - it must be preserved!

### Watch Mode

```bash
# Auto-synthesize on file changes
npm run watch:synth
```

## Troubleshooting

### "Helm not found" Error

```bash
# Install Helm via Nix
nix profile install nixpkgs#kubernetes-helm

# Verify
helm version
```

### "Chart type 'XYZ' not registered"

Chart wasn't auto-registered. Check:
1. Chart class exported from file
2. File located in `charts/` subdirectory
3. No TypeScript errors preventing load

### Import Errors

```bash
# Clean and regenerate
rm -rf node_modules/.cache
npm run import
```

### kagent.dev.ts Missing Types

```bash
# Restore from git
git checkout HEAD -- imports/kagent.dev.ts
```

## Repository Structure

```
cdk8s/
├── charts/              # Chart definitions
│   ├── apps/           # Application charts
│   ├── infra/          # Infrastructure charts
│   ├── pipelines/      # Kargo pipeline charts
│   ├── platform/       # Platform service charts
│   └── secrets/        # External Secrets charts
├── config/             # Application configurations
│   └── applications.ts # Declarative app config
├── crds/               # Vendored CRD files (committed)
├── imports/            # Generated TypeScript types (mostly gitignored)
│   └── kagent.dev.ts  # ⚠️ Exception: committed to repo
├── lib/                # Shared libraries
├── dist/               # Synthesized manifests (gitignored)
└── cdk8s.yaml         # CDK8s configuration
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Synthesize Manifests
on: [push, pull_request]

jobs:
  synth:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Helm
        run: |
          curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

      - name: Install dependencies
        working-directory: cdk8s
        run: npm ci

      - name: Import CRDs
        working-directory: cdk8s
        run: npm run import

      - name: Synthesize manifests
        working-directory: cdk8s
        run: npm run synth

      - name: Upload manifests
        uses: actions/upload-artifact@v4
        with:
          name: kubernetes-manifests
          path: cdk8s/dist/
```

## Further Reading

- [CDK8s Documentation](https://cdk8s.io/)
- [CNOE Project](https://cnoe.io/)
- [IdpBuilder Guide](https://cnoe.io/docs/reference-implementation/installations/idpbuilder)
- [Project Documentation](/workspaces/stacks/docs/)
