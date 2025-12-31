# Research: Nixidy Migration

**Feature**: 114-nixidy
**Date**: 2025-12-31
**Purpose**: Resolve technical unknowns for cdk8s → nixidy migration

## Research Areas

### 1. Nixidy Project Structure

**Decision**: Use flake-based setup with environment-specific modules

**Rationale**:
- Flakes provide reproducible builds with locked dependencies
- Environment-specific modules (`kind.nix`, `talos.nix`) align with current `CLUSTER_TYPE` pattern
- NixOS module system enables configuration inheritance and overrides

**Project Structure**:
```
nixidy/
├── flake.nix                    # Entry point
├── flake.lock                   # Locked dependencies
├── env/
│   ├── base.nix                # Shared configuration
│   ├── kind.nix                # KIND: cnoe:// URLs, localtest.me
│   ├── talos.nix               # Talos: GitHub URLs, TLS, Azure
│   └── variables.nix           # Environment variable handling
├── apps/                        # Application definitions
│   ├── default.nix             # Imports all applications
│   └── <app-name>.nix          # Individual applications
├── modules/                     # Custom modules
│   ├── argocd-application.nix  # ArgoCD Application generation
│   └── kustomization.nix       # Kustomization file generation
├── generated/                   # CRD options (auto-generated)
└── lib/                         # Helper functions
```

**Alternatives Considered**:
- Non-flake setup with npins: Rejected - less reproducible, more complex dependency management
- Single-file configuration: Rejected - 80+ apps would be unmaintainable in one file

---

### 2. Environment Variable Injection

**Decision**: Use `builtins.getEnv` for runtime env vars + module options for typed configuration

**Rationale**:
- Nix's `builtins.getEnv` reads environment variables at evaluation time
- Module options provide type safety and default values
- Combination supports both required and optional variables

**Implementation Pattern**:

```nix
# env/variables.nix
{ lib, ... }:
let
  # Read environment variables with fallbacks
  clusterName = builtins.getEnv "CLUSTER_NAME";
  clusterHost = builtins.getEnv "CLUSTER_HOST";
  ingressHost = builtins.getEnv "INGRESS_HOST";

  # Azure variables (required for Talos)
  azureClientId = builtins.getEnv "AZURE_CLIENT_ID";
  azureTenantId = builtins.getEnv "AZURE_TENANT_ID";
  azureKeyVaultName = builtins.getEnv "AZURE_KEYVAULT_NAME";

  # Git variables
  gitRepoUrl = builtins.getEnv "GIT_REPO_URL";
  gitBranch = let b = builtins.getEnv "GIT_BRANCH"; in if b == "" then "main" else b;
in
{
  options.cluster = {
    name = lib.mkOption {
      type = lib.types.str;
      default = if clusterName != "" then clusterName else clusterHost;
      description = "Cluster identifier";
    };
    ingressHost = lib.mkOption {
      type = lib.types.str;
      default = if ingressHost != "" then ingressHost else "cnoe.localtest.me";
    };
  };

  options.azure = {
    clientId = lib.mkOption {
      type = lib.types.str;
      default = azureClientId;
    };
    tenantId = lib.mkOption {
      type = lib.types.str;
      default = azureTenantId;
    };
    keyVaultName = lib.mkOption {
      type = lib.types.str;
      default = if azureKeyVaultName != "" then azureKeyVaultName else "idp-kv";
    };
  };

  options.git = {
    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = if gitRepoUrl != "" then gitRepoUrl
                else "https://github.com/PittampalliOrg/stacks.git";
    };
    branch = lib.mkOption {
      type = lib.types.str;
      default = gitBranch;
    };
  };
}
```

**Current cdk8s Variables Mapped**:

| Variable | Current Usage | Nixidy Approach |
|----------|---------------|-----------------|
| `CLUSTER_TYPE` | Filter apps, determine URLs | Flake selector: `.#kind` or `.#talos` |
| `CLUSTER_NAME` | Tailscale service names | `config.cluster.name` |
| `CLUSTER_HOST` | Legacy fallback | Merged with CLUSTER_NAME |
| `INGRESS_HOST` | Ingress hostnames | `config.cluster.ingressHost` |
| `AZURE_CLIENT_ID` | Workload identity | `config.azure.clientId` |
| `AZURE_TENANT_ID` | Workload identity | `config.azure.tenantId` |
| `AZURE_KEYVAULT_NAME` | ESO ClusterSecretStore | `config.azure.keyVaultName` |
| `GIT_REPO_URL` | Talos ArgoCD sources | `config.git.repoUrl` |
| `GIT_BRANCH` | Talos ArgoCD sources | `config.git.branch` |
| `KUBECTL_IMAGE` | Job containers | Per-application option |
| `ENVIRONMENT` | ArgoCD labels | Derived from environment name |

**Alternatives Considered**:
- Pass all vars as flake inputs: Rejected - requires command-line flags, not ergonomic
- Use a JSON config file: Rejected - adds indirection, environment vars are simpler
- Hardcode per-environment: Rejected - loses flexibility for cluster-specific values

---

### 3. Multi-Environment Configuration

**Decision**: Use nixidy's `nixidy.lib.mkEnvs` with environment-specific module imports

**Rationale**:
- Native nixidy pattern for multi-environment support
- Each environment gets its own build target
- Module imports enable configuration inheritance

**Implementation Pattern**:

```nix
# flake.nix
{
  description = "Stacks GitOps Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixidy.url = "github:arnarg/nixidy";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixidy, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        nixidyEnvs = nixidy.lib.mkEnvs {
          inherit pkgs;
          envs = {
            # KIND local development
            kind = {
              modules = [
                ./env/base.nix
                ./env/variables.nix
                ./env/kind.nix
                ./apps
              ];
            };

            # Talos production
            talos = {
              modules = [
                ./env/base.nix
                ./env/variables.nix
                ./env/talos.nix
                ./apps
              ];
            };
          };
        };

        packages = {
          nixidy = nixidy.packages.${system}.default;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ nixidy.packages.${system}.default ];
        };
      }
    );
}
```

```nix
# env/kind.nix
{ config, lib, ... }:
{
  nixidy.target.repository = "cnoe://";
  nixidy.target.branch = "main";

  # KIND uses cnoe:// URLs for local development
  nixidy.defaults.source = {
    repoURL = "cnoe://";
    path = "manifests";
  };

  # No TLS, localtest.me domain
  cluster.ingressHost = lib.mkDefault "cnoe.localtest.me";
}
```

```nix
# env/talos.nix
{ config, lib, ... }:
{
  nixidy.target.repository = config.git.repoUrl;
  nixidy.target.branch = config.git.branch;

  # Talos uses GitHub URLs
  nixidy.defaults.source = {
    repoURL = config.git.repoUrl;
    path = "cdk8s/dist";
    targetRevision = config.git.branch;
  };

  # Production domain with TLS
  cluster.ingressHost = lib.mkDefault "ai401kchat.com";

  # Validate required Azure variables
  assertions = [
    {
      assertion = config.azure.clientId != "";
      message = "AZURE_CLIENT_ID is required for Talos environment";
    }
    {
      assertion = config.azure.tenantId != "";
      message = "AZURE_TENANT_ID is required for Talos environment";
    }
  ];
}
```

**Build Commands**:
```bash
# Build for KIND
nixidy build .#kind

# Build for Talos
AZURE_CLIENT_ID=xxx AZURE_TENANT_ID=yyy nixidy build .#talos
```

**Alternatives Considered**:
- Single environment with conditionals: Rejected - harder to maintain, violates nixidy patterns
- Separate flakes per environment: Rejected - duplication, harder to share configuration

---

### 4. Application Definition Patterns

**Decision**: One Nix file per application with typed options

**Rationale**:
- Mirrors current cdk8s chart structure
- Enables independent development and testing
- Clear ownership and discoverability

**Application Pattern**:

```nix
# apps/backstage.nix
{ config, lib, pkgs, ... }:
let
  inherit (config.cluster) ingressHost;
  clusterType = config.nixidy.env;
  isKind = clusterType == "kind";
  isTalos = clusterType == "talos";
in
{
  # Only include for matching cluster type
  config = lib.mkIf (isKind || isTalos) {
    applications.backstage = {
      namespace = "backstage";
      createNamespace = true;

      # Sync wave for ordering
      syncPolicy.annotations."argocd.argoproj.io/sync-wave" = "100";

      resources = {
        # Namespace
        namespaces.backstage = {
          metadata.labels."app.kubernetes.io/managed-by" = "nixidy";
        };

        # ServiceAccount
        serviceAccounts.backstage = { };

        # Deployment
        deployments.backstage.spec = {
          replicas = 1;
          selector.matchLabels.app = "backstage";

          template = {
            metadata.labels.app = "backstage";

            spec = {
              serviceAccountName = "backstage";
              containers.backstage = {
                image = "docker.io/vpittamp23/backstage:1.1.0";
                ports.http.containerPort = 7007;

                env = [
                  { name = "LOG_LEVEL"; value = "debug"; }
                  { name = "NODE_TLS_REJECT_UNAUTHORIZED"; value = "0"; }
                ];

                envFrom = [
                  { secretRef.name = "backstage-env-vars"; }
                  { secretRef.name = "gitea-credentials"; }
                ];
              };
            };
          };
        };

        # Service
        services.backstage.spec = {
          selector.app = "backstage";
          ports.http = {
            port = 7007;
            targetPort = "http";
          };
        };

        # Ingress (environment-specific)
        ingresses.backstage.spec = {
          ingressClassName = "nginx";
          rules = [{
            host = ingressHost;
            http.paths = [{
              path = "/backstage";
              pathType = "Prefix";
              backend.service = {
                name = "backstage";
                port.number = 7007;
              };
            }];
          }];

          # TLS only for Talos
          tls = lib.mkIf isTalos [{
            hosts = [ ingressHost ];
            secretName = "backstage-tls";
          }];
        };
      };
    };
  };
}
```

**Cluster Type Filtering**:

```nix
# apps/eso-workload-identity.nix - Talos only
{ config, lib, ... }:
{
  config = lib.mkIf (config.nixidy.env == "talos") {
    applications.eso-workload-identity = {
      namespace = "external-secrets";
      # ... Talos-specific resources
    };
  };
}
```

**Alternatives Considered**:
- All apps in one file: Rejected - unmaintainable at 80+ apps
- Separate directories per app: Rejected - over-engineering for single-file definitions

---

### 5. ArgoCD Integration

**Decision**: Use nixidy's built-in App-of-Apps generation + custom module for idpBuilder structure

**Rationale**:
- nixidy automatically generates ArgoCD Applications
- Custom module needed to match idpBuilder's expected package structure

**ArgoCD Application Generation**:

nixidy automatically creates `apps/Application-<name>.yaml` for each defined application. Configuration:

```nix
# env/base.nix
{
  nixidy.appOfApps = {
    name = "apps";
    namespace = "argocd";
  };

  nixidy.defaults = {
    destination.server = "https://kubernetes.default.svc";
    project = "default";

    syncPolicy = {
      automated = {
        prune = true;
        selfHeal = true;
      };
      syncOptions = [
        "CreateNamespace=true"
        "ServerSideApply=true"
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

**Custom Module for idpBuilder Package Structure**:

```nix
# modules/idpbuilder.nix
{ config, lib, pkgs, ... }:
{
  # Post-build hook to reorganize output
  # nixidy outputs: result/<app>/
  # idpBuilder expects: dist/<app>.yaml + dist/<app>/manifests/

  nixidy.target.rootPath = "./dist";

  # Each application gets its own directory
  # The ArgoCD Application is moved to package root
}
```

**Sync Wave Implementation**:

```nix
# lib/sync-wave.nix
{ lib }:
{
  # Sync wave helpers matching current cdk8s patterns
  waves = {
    crds = "-120";
    namespaces = "-110";
    rbac = "-90";
    secrets = "-70";
    deployment = "0";
    ingress = "100";
  };

  withSyncWave = wave: resources:
    lib.mapAttrs (name: resource:
      resource // {
        metadata = (resource.metadata or {}) // {
          annotations = (resource.metadata.annotations or {}) // {
            "argocd.argoproj.io/sync-wave" = wave;
          };
        };
      }
    ) resources;
}
```

**Alternatives Considered**:
- Manual Application YAML: Rejected - duplicates nixidy's built-in functionality
- Separate ArgoCD repository: Rejected - violates monorepo pattern

---

### 6. CRD Handling

**Decision**: Generate typed Nix options from CRD YAML files using nixidy generators

**Rationale**:
- Type-safe CRD definitions
- IDE completion for custom resources
- Validation at build time

**CRD Generation**:

```nix
# In flake.nix
packages.generators = {
  # ArgoCD CRDs
  argocd = nixidy.packages.${system}.generators.fromCRD {
    name = "argocd";
    src = pkgs.fetchFromGitHub {
      owner = "argoproj";
      repo = "argo-cd";
      rev = "v2.9.0";
      hash = "sha256-...";
    };
    crds = [
      "manifests/crds/application-crd.yaml"
      "manifests/crds/appproject-crd.yaml"
    ];
  };

  # External Secrets CRDs
  externalSecrets = nixidy.packages.${system}.generators.fromCRD {
    name = "external-secrets";
    src = pkgs.fetchFromGitHub {
      owner = "external-secrets";
      repo = "external-secrets";
      rev = "v0.9.0";
      hash = "sha256-...";
    };
    crds = [ "deploy/crds/*.yaml" ];
  };

  # Kargo CRDs
  kargo = nixidy.packages.${system}.generators.fromCRD {
    name = "kargo";
    src = pkgs.fetchFromGitHub {
      owner = "akuity";
      repo = "kargo";
      rev = "v0.7.0";
      hash = "sha256-...";
    };
    crds = [ "charts/kargo/crds/*.yaml" ];
  };
};
```

**Using Generated CRDs**:

```nix
# env/base.nix
{
  nixidy.applicationImports = [
    ./generated/argocd.nix
    ./generated/external-secrets.nix
    ./generated/kargo.nix
  ];
}

# apps/my-app.nix
{
  applications.my-app.resources = {
    # Now fully typed!
    externalSecrets.my-secret.spec = {
      refreshInterval = "1h";
      secretStoreRef = {
        name = "azure-keyvault-store";
        kind = "ClusterSecretStore";
      };
      target.name = "my-secret";
      data = [
        {
          secretKey = "password";
          remoteRef = {
            key = "my-password";
          };
        }
      ];
    };
  };
}
```

**Raw YAML Fallback**:

For CRDs without generated options, use `yamls`:

```nix
{
  applications.my-app.yamls = [
    ''
      apiVersion: some.custom.io/v1
      kind: CustomResource
      metadata:
        name: example
      spec:
        field: value
    ''
  ];
}
```

---

### 7. Output Structure Compatibility

**Decision**: Custom post-processing to match idpBuilder expected structure

**Rationale**:
- idpBuilder requires specific package structure
- nixidy's default output differs slightly
- Post-processing ensures compatibility

**Expected Structure (idpBuilder)**:
```
dist/
├── backstage.yaml              # ArgoCD Application at package root
└── backstage/
    └── manifests/
        ├── Deployment-backstage.yaml
        ├── Service-backstage.yaml
        ├── Ingress-backstage.yaml
        └── kustomization.yaml
```

**Nixidy Default Output**:
```
result/
├── apps/
│   └── Application-backstage.yaml
└── backstage/
    ├── Deployment-backstage.yaml
    ├── Service-backstage.yaml
    └── ...
```

**Restructuring Script**:

```bash
#!/usr/bin/env bash
# scripts/nixidy-to-idpbuilder.sh

NIXIDY_OUT="$1"  # e.g., result/
OUTPUT_DIR="${2:-dist}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Process each application
for app_dir in "$NIXIDY_OUT"/*/; do
    app_name=$(basename "$app_dir")

    # Skip special directories
    [[ "$app_name" == "apps" ]] && continue

    # Create package structure
    mkdir -p "$OUTPUT_DIR/$app_name/manifests"

    # Copy manifests
    cp "$app_dir"/*.yaml "$OUTPUT_DIR/$app_name/manifests/"

    # Generate kustomization.yaml
    (
        cd "$OUTPUT_DIR/$app_name/manifests"
        echo "apiVersion: kustomize.config.k8s.io/v1beta1"
        echo "kind: Kustomization"
        echo "resources:"
        for f in *.yaml; do
            [[ "$f" != "kustomization.yaml" ]] && echo "  - $f"
        done
    ) > "$OUTPUT_DIR/$app_name/manifests/kustomization.yaml"

    # Move ArgoCD Application to package root
    if [[ -f "$NIXIDY_OUT/apps/Application-$app_name.yaml" ]]; then
        cp "$NIXIDY_OUT/apps/Application-$app_name.yaml" "$OUTPUT_DIR/$app_name.yaml"
    fi
done
```

**Alternatives Considered**:
- Modify nixidy source: Rejected - maintenance burden, upstream divergence
- Accept different structure: Rejected - breaks idpBuilder compatibility
- Wrapper script in flake: Accepted - clean separation of concerns

---

## Summary of Decisions

| Area | Decision | Key Rationale |
|------|----------|---------------|
| Project Structure | Flake-based with env modules | Reproducible, matches nixidy patterns |
| Environment Variables | `builtins.getEnv` + module options | Type-safe with runtime flexibility |
| Multi-Environment | `nixidy.lib.mkEnvs` with kind/talos | Native nixidy pattern |
| Application Definition | One Nix file per app | Maintainable, mirrors cdk8s structure |
| ArgoCD Integration | Built-in + custom module | Leverages nixidy's App-of-Apps |
| CRD Handling | Generated Nix options | Type-safe custom resources |
| Output Structure | Post-processing script | idpBuilder compatibility |

## Open Questions Resolved

1. **How does nixidy handle Helm charts?** → Can import Helm charts via `lib.helm.downloadHelmChart`, but prefer native Nix for maintainability
2. **Can nixidy use kustomize?** → Yes, but defeats the purpose; use native Nix overlays instead
3. **Is builtins.getEnv impure?** → Yes, but acceptable for environment-specific builds; Nix handles purity at flake level
4. **Output structure mismatch?** → Solved with post-processing script
