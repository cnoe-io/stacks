# Cert-Manager - TLS Certificate Management
# Provides Let's Encrypt certificate automation for Talos clusters.
# KIND uses localtest.me which doesn't require TLS certificates.
#
# Dependency chain: cert-manager → cert-manager-secrets → cloudflare-issuer
# Mirrors: cdk8s/config/applications.ts cert-manager entries
{ config, lib, ... }:
let
  isTalos = config.environmentType == "talos";
  namespace = "cert-manager";
in
{
  config = lib.mkIf isTalos {
    # Cert-Manager CRDs - install first
    applications.cert-manager-crds = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-110";  # Very early, CRDs first
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = false;  # Don't prune CRDs to avoid data loss
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
          replace = true;  # CRDs need replace for updates
        };
      };

      # CRDs placeholder - in production, pull from cert-manager releases
      yamls = [
        ''
          # CRDs will be pulled from cert-manager official repository
          # This is a placeholder - actual CRDs should be downloaded from:
          # https://github.com/cert-manager/cert-manager/releases
        ''
      ];
    };

    # Cert-Manager Controller
    # For production, use nixhelm with helm.releases or pre-rendered templates
    applications.cert-manager = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-95";  # After CRDs, before secrets
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
      # Chart: cert-manager from https://charts.jetstack.io
      # Version: v1.14.4
      yamls = [
        ''
          # Placeholder: cert-manager would be deployed via Helm
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases.cert-manager
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered Helm templates
          #
          # Key values:
          # - installCRDs = false (managed separately)
          # - replicaCount = 1
          # - webhook.replicaCount = 1
          # - cainjector.replicaCount = 1
        ''
      ];
    };

    # NOTE: cert-manager-secrets and cloudflare-issuer are defined in secrets.nix
  };
}
