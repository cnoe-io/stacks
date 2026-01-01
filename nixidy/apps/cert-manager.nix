# Cert-Manager - TLS Certificate Management
# Provides Let's Encrypt certificate automation for Talos clusters.
# KIND uses localtest.me which doesn't require TLS certificates.
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# Dependency chain: cert-manager → cert-manager-secrets → cloudflare-issuer
# Mirrors: cdk8s/config/applications.ts cert-manager entries
{ config, lib, charts, ... }:
let
  isTalos = config.environmentType == "talos";
  namespace = "cert-manager";
in
{
  config = lib.mkIf isTalos {
    # Cert-Manager - includes CRDs with installCRDs=true
    applications.cert-manager = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-95";  # Early, before secrets
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

      # Use nixhelm for pre-rendered Helm chart
      helm.releases.cert-manager = {
        chart = charts.jetstack.cert-manager;
        values = {
          installCRDs = true;
          replicaCount = 1;
          webhook = {
            replicaCount = 1;
          };
          cainjector = {
            replicaCount = 1;
          };
        };
      };
    };

    # NOTE: cert-manager-secrets and cloudflare-issuer are defined in secrets.nix
  };
}
