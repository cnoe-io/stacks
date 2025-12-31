# Quickstart: Nixidy Migration

**Feature**: 114-nixidy
**Date**: 2025-12-31
**Purpose**: Guide for developers using the nixidy configuration

## Prerequisites

1. **Nix with Flakes**: Ensure Nix is installed with flakes enabled
   ```bash
   # Check Nix version
   nix --version

   # Verify flakes are enabled
   nix flake --help
   ```

2. **nixidy CLI**: Installed via the flake's devShell
   ```bash
   cd nixidy
   nix develop  # Enters shell with nixidy available
   ```

## Quick Commands

### Build Manifests

```bash
cd nixidy

# Build for KIND (local development)
nix build .#nixidyEnvs.x86_64-linux.kind.result

# Build for Talos (production)
AZURE_CLIENT_ID=xxx AZURE_TENANT_ID=yyy nix build .#nixidyEnvs.x86_64-linux.talos.result

# Build for Hub (multi-cluster management)
nix build .#nixidyEnvs.x86_64-linux.hub.result

# Copy output to nixidy-dist (for idpBuilder)
rm -rf ../nixidy-dist/* && cp -rL result/* ../nixidy-dist/
```

### Deploy

```bash
# KIND: Use idpBuilder
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update

# Or deploy specific application
idpbuilder create --package nixidy-dist/<app>

# Talos: Use ArgoCD bootstrap scripts
cd ../scripts
./bootstrap-cluster.sh
```

### Validate

```bash
# Compare nixidy output structure
ls -la nixidy-dist/*.yaml | wc -l

# Verify ArgoCD applications
argocd app list --insecure

# Check application health
argocd app get argocd/backstage --insecure
```

## Directory Structure

```
nixidy/
├── flake.nix           # Entry point - defines environments
├── env/
│   ├── base.nix       # Shared configuration
│   ├── kind.nix       # KIND-specific settings
│   ├── talos.nix      # Talos-specific settings
│   └── variables.nix  # Environment variable handling
├── apps/
│   ├── default.nix    # Imports all applications
│   ├── backstage.nix  # Backstage application
│   └── ...            # Other applications
├── modules/           # Custom nixidy modules
├── lib/               # Shared functions
└── generated/         # CRD type definitions
```

## Adding a New Application

### 1. Create Application File

```bash
# Create new application file
touch nixidy/apps/my-app.nix
```

### 2. Define the Application

```nix
# nixidy/apps/my-app.nix
{ config, lib, ... }:
let
  inherit (config.cluster) ingressHost;
in
{
  applications.my-app = {
    namespace = "my-app";
    createNamespace = true;

    # Sync wave (optional, default: "0")
    syncPolicy.syncWave = "100";

    # Labels for ArgoCD
    labels = {
      "app.kubernetes.io/component" = "backend";
      "app.kubernetes.io/part-of" = "my-stack";
    };

    resources = {
      # Deployment
      deployments.my-app.spec = {
        replicas = 2;
        selector.matchLabels.app = "my-app";

        template = {
          metadata.labels.app = "my-app";
          spec.containers.my-app = {
            image = "my-registry/my-app:latest";
            ports.http.containerPort = 8080;

            env = [
              { name = "ENV"; value = "production"; }
            ];

            resources = {
              requests = {
                cpu = "100m";
                memory = "128Mi";
              };
              limits = {
                cpu = "500m";
                memory = "512Mi";
              };
            };
          };
        };
      };

      # Service
      services.my-app.spec = {
        selector.app = "my-app";
        ports.http = {
          port = 80;
          targetPort = "http";
        };
      };

      # Ingress
      ingresses.my-app.spec = {
        ingressClassName = "nginx";
        rules = [{
          host = "${ingressHost}";
          http.paths = [{
            path = "/my-app";
            pathType = "Prefix";
            backend.service = {
              name = "my-app";
              port.number = 80;
            };
          }];
        }];
      };
    };
  };
}
```

### 3. Register the Application

```nix
# nixidy/apps/default.nix
{
  imports = [
    ./backstage.nix
    ./keycloak.nix
    ./my-app.nix  # Add this line
  ];
}
```

### 4. Build and Verify

```bash
# Build manifests
nixidy build .#kind

# Check output
ls result/my-app/
cat result/apps/Application-my-app.yaml
```

## Environment-Specific Configuration

### KIND vs Talos

```nix
# apps/my-app.nix
{ config, lib, ... }:
let
  isKind = config.nixidy.env == "kind";
  isTalos = config.nixidy.env == "talos";
in
{
  applications.my-app = {
    namespace = "my-app";

    resources = {
      deployments.my-app.spec = {
        # More replicas in production
        replicas = if isTalos then 3 else 1;

        template.spec.containers.my-app = {
          image = "my-registry/my-app:latest";

          # Different env vars per environment
          env = [
            { name = "ENV"; value = config.nixidy.env; }
          ] ++ lib.optionals isTalos [
            { name = "ENABLE_TLS"; value = "true"; }
          ];
        };
      };

      # TLS only for Talos
      ingresses.my-app.spec.tls = lib.mkIf isTalos [{
        hosts = [ config.cluster.ingressHost ];
        secretName = "my-app-tls";
      }];
    };
  };
}
```

### Cluster-Specific Applications

```nix
# apps/talos-only-app.nix
{ config, lib, ... }:
{
  # Only deploy to Talos
  config = lib.mkIf (config.nixidy.env == "talos") {
    applications.talos-only-app = {
      namespace = "talos-only";
      # ...
    };
  };
}
```

## Using External Secrets

```nix
# apps/my-app.nix
{
  applications.my-app.resources = {
    # ExternalSecret (requires generated CRD options)
    externalSecrets.my-app-secrets.spec = {
      refreshInterval = "1h";
      secretStoreRef = {
        name = "azure-keyvault-store";
        kind = "ClusterSecretStore";
      };
      target.name = "my-app-secrets";
      data = [
        {
          secretKey = "database-password";
          remoteRef.key = "my-app-db-password";
        }
        {
          secretKey = "api-key";
          remoteRef.key = "my-app-api-key";
        }
      ];
    };

    deployments.my-app.spec.template.spec.containers.my-app = {
      envFrom = [
        { secretRef.name = "my-app-secrets"; }
      ];
    };
  };
}
```

## Common Patterns

### Sync Waves

```nix
{
  applications.my-database = {
    syncPolicy.syncWave = "-50";  # Deploy early
  };

  applications.my-app = {
    syncPolicy.syncWave = "0";  # Deploy after database
  };

  applications.my-ingress = {
    syncPolicy.syncWave = "100";  # Deploy last
  };
}
```

### ArgoCD Sync Policy

```nix
{
  applications.my-app = {
    syncPolicy = {
      automated = {
        prune = true;
        selfHeal = true;
      };
      syncOptions = [
        "CreateNamespace=true"
        "ServerSideApply=true"
        "ApplyOutOfSyncOnly=true"
      ];
      retry = {
        limit = 5;
        backoff = {
          duration = "5s";
          factor = 2;
          maxDuration = "3m";
        };
      };
    };
  };
}
```

### Ignore Differences

```nix
{
  applications.my-app = {
    ignoreDifferences = [
      {
        group = "apps";
        kind = "Deployment";
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations"
        ];
      }
    ];
  };
}
```

## Troubleshooting

### Build Errors

```bash
# Check for Nix evaluation errors
nix flake check

# Show detailed error trace
nixidy build .#kind --show-trace
```

### Missing CRD Types

```bash
# Regenerate CRD options
nix build .#generators.external-secrets
cp result generated/external-secrets.nix
```

### Environment Variables Not Working

```bash
# Verify environment variables are set
echo $AZURE_CLIENT_ID
echo $AZURE_TENANT_ID

# Build with explicit env vars
AZURE_CLIENT_ID=xxx AZURE_TENANT_ID=yyy nixidy build .#talos
```

## Comparison: cdk8s vs nixidy

| Task | cdk8s | nixidy |
|------|-------|--------|
| Build | `npm run synth` | `nixidy build .#kind` |
| Add app | Edit `applications.ts` + create chart class | Create `apps/<name>.nix` + import |
| Environment | `CLUSTER_TYPE=kind` | Flake selector `.#kind` |
| Type safety | TypeScript interfaces | Nix module options |
| CRDs | `npm run import` | `nix build .#generators.<crd>` |
| Output | `dist/<app>/manifests/` | `result/<app>/` → processed to `dist/` |

## Final Validation Steps

### 1. Build All Environments

```bash
cd nixidy

# Build KIND environment (local development)
nix build .#nixidyEnvs.x86_64-linux.kind.result
cp -rL result/* ../nixidy-dist/

# Build Talos environment (production)
AZURE_CLIENT_ID=xxx AZURE_TENANT_ID=yyy nix build .#nixidyEnvs.x86_64-linux.talos.result

# Build Hub environment (multi-cluster management)
nix build .#nixidyEnvs.x86_64-linux.hub.result
```

### 2. Verify Application Count

```bash
# Check number of generated applications
ls -la nixidy-dist/*.yaml | wc -l
# Expected: 28+ applications for KIND

# List all application names
ls nixidy-dist/*.yaml | xargs -I{} basename {} .yaml | sort
```

### 3. Validate Manifest Structure

```bash
# Each application should have:
# - Root YAML (nixidy-dist/<app>.yaml)
# - Manifests directory (nixidy-dist/<app>/manifests/)

# Check backstage as example
ls -la nixidy-dist/backstage/manifests/
# Expected: Deployment, Service, Ingress, etc.

# Validate YAML syntax
for f in nixidy-dist/*/*.yaml nixidy-dist/*/*/*.yaml; do
  yq e '.' "$f" > /dev/null || echo "Invalid YAML: $f"
done
```

### 4. Deploy to KIND Cluster

```bash
# Using idpBuilder
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update

# Or deploy specific app
idpbuilder create --package nixidy-dist/backstage

# Verify in ArgoCD
argocd app list --insecure
```

### 5. Performance Validation

```bash
# Target: <60 seconds for full build
time nix build .#nixidyEnvs.x86_64-linux.kind.result

# Incremental builds should be nearly instant due to Nix caching
time nix build .#nixidyEnvs.x86_64-linux.kind.result
```

## Next Steps

1. Run `nix build .#nixidyEnvs.x86_64-linux.kind.result` to generate manifests
2. Copy output with `cp -rL result/* ../nixidy-dist/`
3. Deploy to KIND cluster with `cluster-update`
4. Verify in ArgoCD UI at `https://argocd.cnoe.localtest.me:8443`
