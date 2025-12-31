# Data Model: Nixidy Configuration Schema

**Feature**: 114-nixidy
**Date**: 2025-12-31
**Purpose**: Define the configuration schema for nixidy migration

## Overview

This document defines the configuration model for nixidy, mapping from the current cdk8s `ApplicationConfig` TypeScript interface to Nix module options.

## Entity Definitions

### 1. Application

An application is a deployable unit consisting of Kubernetes resources and ArgoCD configuration.

**Current cdk8s Type** (`lib/idpbuilder-types.ts`):
```typescript
interface ApplicationConfig {
  name: string;
  namespace: string;
  clusterType?: 'kind' | 'talos' | 'both';
  clusterNames?: string[];
  sourcePath?: string;
  skipSynthesis?: boolean;
  directoryExclude?: string;
  chart?: {
    type: string;
    props?: Record<string, any>;
  };
  dependencies?: Record<string, { type: string; props?: Record<string, any> }>;
  argocd?: ArgoCDConfig;
}
```

**Nixidy Module Options** (`modules/application.nix`):

```nix
{ lib, ... }:
{
  options.applications = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
      options = {
        # Core fields
        namespace = lib.mkOption {
          type = lib.types.str;
          description = "Target Kubernetes namespace";
        };

        createNamespace = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Auto-create namespace if it doesn't exist";
        };

        # Cluster targeting (replaces clusterType)
        clusterTypes = lib.mkOption {
          type = lib.types.listOf (lib.types.enum [ "kind" "talos" ]);
          default = [ "kind" "talos" ];  # 'both' is the default
          description = "Which cluster types this app is deployed to";
        };

        clusterNames = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "Optional: Only deploy to specific cluster names";
        };

        # ArgoCD configuration
        syncPolicy = lib.mkOption {
          type = lib.types.submodule {
            options = {
              syncWave = lib.mkOption {
                type = lib.types.str;
                default = "0";
                description = "ArgoCD sync wave for ordering";
              };

              automated = lib.mkOption {
                type = lib.types.submodule {
                  options = {
                    prune = lib.mkOption { type = lib.types.bool; default = true; };
                    selfHeal = lib.mkOption { type = lib.types.bool; default = true; };
                    allowEmpty = lib.mkOption { type = lib.types.bool; default = false; };
                  };
                };
                default = { };
              };

              syncOptions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "CreateNamespace=true" "ServerSideApply=true" ];
              };

              retry = lib.mkOption {
                type = lib.types.nullOr (lib.types.submodule {
                  options = {
                    limit = lib.mkOption { type = lib.types.int; default = 5; };
                    backoff = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          duration = lib.mkOption { type = lib.types.str; default = "5s"; };
                          factor = lib.mkOption { type = lib.types.int; default = 2; };
                          maxDuration = lib.mkOption { type = lib.types.str; default = "3m"; };
                        };
                      };
                      default = { };
                    };
                  };
                });
                default = null;
              };
            };
          };
          default = { };
        };

        labels = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "ArgoCD Application labels";
        };

        annotations = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "ArgoCD Application annotations";
        };

        ignoreDifferences = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              group = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              kind = lib.mkOption { type = lib.types.str; };
              name = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              jsonPointers = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
            };
          });
          default = [ ];
        };

        sources = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.submodule {
            options = {
              repoURL = lib.mkOption { type = lib.types.str; };
              path = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              targetRevision = lib.mkOption { type = lib.types.str; default = "main"; };
              chart = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              helm = lib.mkOption { type = lib.types.nullOr lib.types.attrs; default = null; };
              ref = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            };
          }));
          default = null;
          description = "Multi-source configuration for ArgoCD";
        };

        targetCluster = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum [ "hub" "hetzner" "thinkpad" "ryzen" "talos" ]);
          default = null;
          description = "Target cluster for hub-and-spoke deployment";
        };

        # Kubernetes resources (nixidy built-in)
        resources = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Kubernetes resources (deployments, services, etc.)";
        };

        # Raw YAML manifests
        yamls = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Raw YAML manifests for unsupported resource types";
        };
      };
    }));
    default = { };
  };
}
```

---

### 2. Environment

An environment represents a target cluster configuration.

**Nixidy Environment Schema**:

```nix
# env/base.nix - Shared environment configuration
{ lib, ... }:
{
  options = {
    nixidy.env = lib.mkOption {
      type = lib.types.str;
      description = "Environment name (kind, talos, etc.)";
    };

    nixidy.target = {
      repository = lib.mkOption {
        type = lib.types.str;
        description = "Git repository URL for ArgoCD source";
      };

      branch = lib.mkOption {
        type = lib.types.str;
        default = "main";
      };

      rootPath = lib.mkOption {
        type = lib.types.str;
        default = "./dist";
        description = "Root path for generated manifests";
      };
    };

    nixidy.defaults = {
      destination = {
        server = lib.mkOption {
          type = lib.types.str;
          default = "https://kubernetes.default.svc";
        };

        namespace = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };

      project = lib.mkOption {
        type = lib.types.str;
        default = "default";
      };

      syncPolicy = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Default sync policy for all applications";
      };

      source = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Default source configuration";
      };
    };

    nixidy.appOfApps = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "apps";
      };

      namespace = lib.mkOption {
        type = lib.types.str;
        default = "argocd";
      };
    };
  };
}
```

---

### 3. Cluster Configuration

Cluster-specific settings for KIND and Talos.

```nix
# lib/cluster-config.nix
{ lib, ... }:
{
  options.cluster = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Cluster identifier (e.g., thinkpad, ryzen, hub)";
    };

    suffix = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Suffix for service names (e.g., -thinkpad)";
    };

    ingressHost = lib.mkOption {
      type = lib.types.str;
      default = "cnoe.localtest.me";
      description = "Base domain for ingress hosts";
    };

    ingressPort = lib.mkOption {
      type = lib.types.int;
      default = 8443;
    };

    tls = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      clusterIssuer = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "cert-manager ClusterIssuer name";
      };
    };
  };

  options.azure = {
    clientId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Azure AD Application Client ID for Workload Identity";
    };

    tenantId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Azure AD Tenant ID";
    };

    keyVaultName = lib.mkOption {
      type = lib.types.str;
      default = "idp-kv";
      description = "Azure Key Vault name for ESO";
    };
  };

  options.tailscale = {
    tailnet = lib.mkOption {
      type = lib.types.str;
      default = "tail286401.ts.net";
      description = "Tailscale tailnet domain";
    };

    authKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Secret name containing Tailscale auth key";
    };
  };

  options.git = {
    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/PittampalliOrg/stacks.git";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
    };
  };
}
```

---

### 4. Sync Wave Mapping

Mapping of sync waves to resource ordering.

```nix
# lib/sync-waves.nix
{
  # CRDs and fundamental resources
  crds = "-120";
  operators = "-110";
  namespaces = "-110";

  # RBAC and security
  rbac = "-90";
  workloadIdentity = "-90";
  secretStores = "-88";

  # Secrets and configuration
  secrets = "-85";
  clusterIssuers = "-80";
  configMaps = "-70";

  # Dependencies
  databases = "-50";
  caches = "-40";

  # Core infrastructure
  infrastructure = "-30";

  # Deployments (default)
  deployments = "0";

  # Post-deployment
  jobs = "10";
  tests = "20";

  # Applications
  applications = "50";

  # Ingress and external access
  ingress = "100";
  tailscaleServe = "110";
}
```

---

## Validation Rules

### Required Fields

| Entity | Field | Condition |
|--------|-------|-----------|
| Application | namespace | Always required |
| Environment (talos) | azure.clientId | Required for Talos |
| Environment (talos) | azure.tenantId | Required for Talos |
| Environment (talos) | git.repoUrl | Required for Talos |

### Assertions

```nix
# env/talos.nix
{
  assertions = [
    {
      assertion = config.azure.clientId != "";
      message = "AZURE_CLIENT_ID environment variable is required for Talos environment";
    }
    {
      assertion = config.azure.tenantId != "";
      message = "AZURE_TENANT_ID environment variable is required for Talos environment";
    }
    {
      assertion = config.git.repoUrl != "";
      message = "GIT_REPO_URL environment variable is required for Talos environment";
    }
  ];
}
```

---

## State Transitions

Applications don't have runtime state - they are build-time configuration that produces static YAML manifests. The state machine is:

```
[Not Defined] --> [Defined in Nix] --> [Built by nixidy] --> [Deployed by ArgoCD]
```

ArgoCD manages the runtime state (Synced, OutOfSync, Healthy, Degraded, etc.).

---

## Migration Mapping

### cdk8s Type → Nixidy Option

| cdk8s Field | Nixidy Equivalent |
|-------------|-------------------|
| `name` | Attribute name in `applications.<name>` |
| `namespace` | `applications.<name>.namespace` |
| `clusterType: 'kind'` | `clusterTypes = [ "kind" ];` |
| `clusterType: 'talos'` | `clusterTypes = [ "talos" ];` |
| `clusterType: 'both'` | `clusterTypes = [ "kind" "talos" ];` (default) |
| `clusterNames` | `clusterNames` |
| `chart.type` | N/A - resources defined inline |
| `chart.props` | Direct attributes in application definition |
| `argocd.syncWave` | `syncPolicy.syncWave` |
| `argocd.labels` | `labels` |
| `argocd.syncPolicy.automated` | `syncPolicy.automated` |
| `argocd.syncPolicy.syncOptions` | `syncPolicy.syncOptions` |
| `argocd.syncPolicy.retry` | `syncPolicy.retry` |
| `argocd.ignoreDifferences` | `ignoreDifferences` |
| `argocd.sources` | `sources` |
| `argocd.targetCluster` | `targetCluster` |

### Chart Class → Nix Module

Each cdk8s chart class becomes a Nix module that defines resources:

| cdk8s Chart | Nixidy Module |
|-------------|---------------|
| `BackstageChart` | `apps/backstage.nix` |
| `KeycloakChart` | `apps/keycloak.nix` |
| `PostgresChart` | `apps/postgres.nix` |
| `RedisChart` | `apps/redis.nix` |
| `TailscaleOperatorChart` | `apps/tailscale-operator.nix` |
| ... | ... |

The chart logic (conditionals, loops, computed values) is translated to Nix expressions.
