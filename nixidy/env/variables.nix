# Nixidy configuration options (schema)
# This module defines the available options - values are set in environment configs
# (kind.nix, talos.nix, hub.nix)
#
# This is the native Nix approach: define options here, set values per-environment.
# No environment variables needed - everything is declarative and reproducible.
{ lib, ... }:
{
  options = {
    # =========================================================================
    # Cluster Configuration
    # =========================================================================
    cluster = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "localdev";
        description = "Cluster identifier for naming resources";
      };

      suffix = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional suffix for cluster-specific naming (e.g., -thinkpad)";
      };

      ingressHost = lib.mkOption {
        type = lib.types.str;
        default = "cnoe.localtest.me";
        description = "Base domain for ingress hosts";
      };

      ingressPort = lib.mkOption {
        type = lib.types.int;
        default = 8443;
        description = "Port for ingress (8443 for KIND, 443 for production)";
      };

      tls = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable TLS for ingress resources";
        };

        clusterIssuer = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "cert-manager ClusterIssuer name";
        };
      };
    };

    # =========================================================================
    # Azure Workload Identity Configuration
    # =========================================================================
    # These are Azure AD identifiers used for Workload Identity federation.
    # Actual secrets remain in Azure Key Vault.
    azure = {
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

      subscriptionId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Azure Subscription ID";
      };

      keyVaultName = lib.mkOption {
        type = lib.types.str;
        default = "idp-kv";
        description = "Azure Key Vault name for External Secrets";
      };
    };

    # =========================================================================
    # Tailscale Configuration
    # =========================================================================
    tailscale = {
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

      # Host identifier for Tailscale Services (stable URLs)
      # Maps to created services like gitea-thinkpad, argocd-thinkpad, etc.
      # Defaults to cluster name, but can be overridden for physical host mapping
      serviceHost = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Host identifier for Tailscale Services (e.g., thinkpad, ryzen, hub)";
      };
    };

    # =========================================================================
    # Git Configuration
    # =========================================================================
    git = {
      repoUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/PittampalliOrg/stacks.git";
        description = "Git repository URL for ArgoCD sources";
      };

      branch = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Git branch for ArgoCD sources";
      };
    };

    # =========================================================================
    # Container Images
    # =========================================================================
    images = {
      kubectl = lib.mkOption {
        type = lib.types.str;
        default = "alpine/kubectl:latest";
        description = "kubectl container image for Jobs";
      };

      nixosImageServer = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "NixOS image server container image";
      };
    };

    # =========================================================================
    # Keycloak Configuration
    # =========================================================================
    keycloak = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://keycloak.cnoe.localtest.me:8443";
        description = "Keycloak base URL (domain-based routing)";
      };

      realm = lib.mkOption {
        type = lib.types.str;
        default = "cnoe";
        description = "Keycloak realm name";
      };
    };

    # =========================================================================
    # Gitea Configuration
    # =========================================================================
    gitea = {
      tailscaleHost = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Gitea Tailscale host for external access";
      };
    };

    # =========================================================================
    # NixOS VM Configuration
    # =========================================================================
    nixosVm = {
      storage = lib.mkOption {
        type = lib.types.str;
        default = "80Gi";
        description = "NixOS VM storage size";
      };

      cpuCores = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "NixOS VM CPU cores";
      };

      memory = lib.mkOption {
        type = lib.types.str;
        default = "6Gi";
        description = "NixOS VM memory allocation";
      };

      tailscaleAuthKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Tailscale auth key for NixOS VMs";
      };
    };

    # =========================================================================
    # Environment Configuration
    # =========================================================================
    environment = lib.mkOption {
      type = lib.types.str;
      default = "dev";
      description = "Environment name (dev, staging, prod)";
    };

    environmentType = lib.mkOption {
      type = lib.types.enum [ "kind" "talos" "hub" ];
      default = "kind";
      description = "Environment type for application filtering (kind, talos, hub)";
    };
  };
}
