# External Secrets Operator - Secret Management
# Provides external secret management for both KIND and Talos clusters.
# KIND uses idpBuilder's built-in Gitea secret stores.
# Talos uses Azure Key Vault via Workload Identity.
#
# Mirrors: cdk8s/config/applications.ts external-secrets entries
{ config, lib, ... }:
let
  isKind = config.environmentType == "kind";
  isTalos = config.environmentType == "talos";
  namespace = "external-secrets";
in
{
  # External Secrets Operator - Helm deployment (both environments)
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

      # Placeholder for Helm chart deployment
      # For production, use nixhelm with helm.releases or ArgoCD Helm source
      # Chart: external-secrets from https://charts.external-secrets.io
      # Version: 0.9.13
      yamls = [
        ''
          # Placeholder: external-secrets would be deployed via Helm
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases.external-secrets
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered Helm templates
          #
          # Key values:
          # - installCRDs = true
          # - webhook.create = true
          # - certController.create = true
          # - serviceAccount.name = "external-secrets"
        ''
      ];
    };

    # Workload Identity for External Secrets (Talos only)
    # This is handled by eso-workload-identity.nix

    # NOTE: bootstrap-secrets is defined in secrets.nix
  };
}
