# External Secrets Operator - Secret Management
# Provides external secret management for both KIND and Talos clusters.
# KIND uses idpBuilder's built-in Gitea secret stores.
# Talos uses Azure Key Vault via Workload Identity.
#
# Uses nixhelm for Helm chart management following nixidy best practices.
# See: https://nixidy.dev/user_guide/helm_charts/
#
# Mirrors: cdk8s/config/applications.ts external-secrets entries
{ config, lib, charts, ... }:
let
  isKind = config.environmentType == "kind";
  isTalos = config.environmentType == "talos";
  namespace = "external-secrets";
in
{
  # External Secrets Operator - Helm deployment via nixhelm
  config = {
    applications.external-secrets = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-100";  # Early, before secrets
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
        };
      };

      # Use nixhelm for pre-rendered Helm chart (nixidy best practice)
      # Chart is rendered at build time, not at ArgoCD sync time
      helm.releases.external-secrets = {
        chart = charts.external-secrets.external-secrets;
        values = {
          installCRDs = true;
          webhook = {
            create = true;
          };
          certController = {
            create = true;
          };
          serviceAccount = {
            create = true;
            name = "external-secrets";
            # Azure Workload Identity annotations for Key Vault access
            labels = {
              "azure.workload.identity/use" = "true";
            };
            annotations = {
              "azure.workload.identity/client-id" = config.azure.clientId;
              "azure.workload.identity/tenant-id" = config.azure.tenantId;
            };
          };
        };
      };
    };

    # Workload Identity for External Secrets (Talos only)
    # This is handled by eso-workload-identity.nix

    # NOTE: bootstrap-secrets is defined in secrets.nix
  };
}
