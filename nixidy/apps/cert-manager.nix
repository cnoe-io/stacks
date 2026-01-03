# Cert-Manager - TLS Certificate Management
# Provides certificate automation for both Talos (Let's Encrypt) and KIND (self-signed).
# KIND uses self-signed certificates for internal services (webhooks, etc.)
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# Dependency chain: cert-manager → cert-manager-secrets → cloudflare-issuer (Talos) / selfsigned-issuer (KIND)
# Mirrors: cdk8s/config/applications.ts cert-manager entries
{ config, lib, charts, ... }:
let
  isTalos = config.environmentType == "talos";
  isKind = config.environmentType == "kind";
  namespace = "cert-manager";
in
{
  config = lib.mkIf (isTalos || isKind) {
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
