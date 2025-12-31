# Environment variable handling for nixidy
# Maps environment variables to typed Nix options
# Mirrors: cdk8s/config/applications.ts, cdk8s/lib/cluster-identity.ts
{ lib, ... }:
let
  # Read environment variables at evaluation time
  getEnvOrDefault = name: default:
    let val = builtins.getEnv name;
    in if val == "" then default else val;

  getEnvInt = name: default:
    let val = builtins.getEnv name;
    in if val == "" then default else builtins.fromJSON val;

  # Cluster identification
  clusterName = getEnvOrDefault "CLUSTER_NAME" "";
  clusterHost = getEnvOrDefault "CLUSTER_HOST" "";
  ingressHost = getEnvOrDefault "INGRESS_HOST" "";
  ingressPort = getEnvOrDefault "INGRESS_PORT" "8443";
  environment = getEnvOrDefault "ENVIRONMENT" "";

  # Azure configuration (required for Talos)
  azureClientId = builtins.getEnv "AZURE_CLIENT_ID";
  azureTenantId = builtins.getEnv "AZURE_TENANT_ID";
  azureKeyVaultName = getEnvOrDefault "AZURE_KEYVAULT_NAME" "idp-kv";
  azureSubscriptionId = builtins.getEnv "AZURE_SUBSCRIPTION_ID";

  # Git configuration
  gitRepoUrl = getEnvOrDefault "GIT_REPO_URL" "https://github.com/PittampalliOrg/stacks.git";
  gitBranch = getEnvOrDefault "GIT_BRANCH" "main";

  # Tailscale configuration
  tailscaleTailnet = getEnvOrDefault "TAILSCALE_TAILNET" "tail286401.ts.net";
  tailscaleAuthKeySecret = getEnvOrDefault "TAILSCALE_AUTH_KEY_SECRET" "";
  tailscaleVmAuthKey = getEnvOrDefault "TAILSCALE_VM_AUTH_KEY" "";

  # Keycloak configuration
  keycloakUrl = getEnvOrDefault "KEYCLOAK_URL" "";
  keycloakRealm = getEnvOrDefault "KEYCLOAK_REALM" "cnoe";

  # Gitea configuration
  giteaTailscaleHost = getEnvOrDefault "GITEA_TAILSCALE_HOST" "";

  # Container images
  kubectlImage = getEnvOrDefault "KUBECTL_IMAGE" "alpine/kubectl:latest";
  nixosImageServerImage = getEnvOrDefault "NIXOS_IMAGE_SERVER_IMAGE" (getEnvOrDefault "NIXOS_SWAY_IMAGE_SERVER_IMAGE" "");

  # NixOS VM configuration
  nixosVmStorage = getEnvOrDefault "NIXOS_VM_STORAGE" "80Gi";
  nixosVmCpuCores = getEnvInt "NIXOS_VM_CPU_CORES" 2;
  nixosVmMemory = getEnvOrDefault "NIXOS_VM_MEMORY" "6Gi";
in
{
  options = {
    cluster = {
      name = lib.mkOption {
        type = lib.types.str;
        default = if clusterName != "" then clusterName
                  else if clusterHost != "" then clusterHost
                  else "localdev";
        description = "Cluster identifier for naming resources";
      };

      suffix = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional suffix for cluster-specific naming (e.g., -thinkpad)";
      };

      ingressHost = lib.mkOption {
        type = lib.types.str;
        default = if ingressHost != "" then ingressHost else "cnoe.localtest.me";
        description = "Base domain for ingress hosts";
      };

      ingressPort = lib.mkOption {
        type = lib.types.int;
        default = lib.toInt ingressPort;
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

    azure = {
      clientId = lib.mkOption {
        type = lib.types.str;
        default = azureClientId;
        description = "Azure AD Application Client ID for Workload Identity";
      };

      tenantId = lib.mkOption {
        type = lib.types.str;
        default = azureTenantId;
        description = "Azure AD Tenant ID";
      };

      subscriptionId = lib.mkOption {
        type = lib.types.str;
        default = azureSubscriptionId;
        description = "Azure Subscription ID";
      };

      keyVaultName = lib.mkOption {
        type = lib.types.str;
        default = azureKeyVaultName;
        description = "Azure Key Vault name for External Secrets";
      };
    };

    tailscale = {
      tailnet = lib.mkOption {
        type = lib.types.str;
        default = tailscaleTailnet;
        description = "Tailscale tailnet domain";
      };

      authKeySecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if tailscaleAuthKeySecret == "" then null else tailscaleAuthKeySecret;
        description = "Secret name containing Tailscale auth key";
      };
    };

    git = {
      repoUrl = lib.mkOption {
        type = lib.types.str;
        default = gitRepoUrl;
        description = "Git repository URL for ArgoCD sources";
      };

      branch = lib.mkOption {
        type = lib.types.str;
        default = gitBranch;
        description = "Git branch for ArgoCD sources";
      };
    };

    images = {
      kubectl = lib.mkOption {
        type = lib.types.str;
        default = kubectlImage;
        description = "kubectl container image for Jobs";
      };

      nixosImageServer = lib.mkOption {
        type = lib.types.str;
        default = nixosImageServerImage;
        description = "NixOS image server container image";
      };
    };

    keycloak = {
      url = lib.mkOption {
        type = lib.types.str;
        default = if keycloakUrl != "" then keycloakUrl
                  else "https://cnoe.localtest.me:8443/keycloak";
        description = "Keycloak base URL";
      };

      realm = lib.mkOption {
        type = lib.types.str;
        default = keycloakRealm;
        description = "Keycloak realm name";
      };
    };

    gitea = {
      tailscaleHost = lib.mkOption {
        type = lib.types.str;
        default = giteaTailscaleHost;
        description = "Gitea Tailscale host for external access";
      };
    };

    nixosVm = {
      storage = lib.mkOption {
        type = lib.types.str;
        default = nixosVmStorage;
        description = "NixOS VM storage size";
      };

      cpuCores = lib.mkOption {
        type = lib.types.int;
        default = nixosVmCpuCores;
        description = "NixOS VM CPU cores";
      };

      memory = lib.mkOption {
        type = lib.types.str;
        default = nixosVmMemory;
        description = "NixOS VM memory allocation";
      };

      tailscaleAuthKey = lib.mkOption {
        type = lib.types.str;
        default = tailscaleVmAuthKey;
        description = "Tailscale auth key for NixOS VMs";
      };
    };

    environment = lib.mkOption {
      type = lib.types.str;
      default = environment;
      description = "Environment name (dev, staging, prod)";
    };

    # Environment type for filtering applications
    environmentType = lib.mkOption {
      type = lib.types.enum [ "kind" "talos" "hub" ];
      default = "kind";
      description = "Environment type for application filtering (kind, talos, hub)";
    };
  };
}
