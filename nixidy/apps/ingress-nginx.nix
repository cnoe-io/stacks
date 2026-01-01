# Ingress NGINX Controller - Disabled by default
# IDPBuilder manages ingress-nginx directly in KIND clusters.
# This app can be enabled for Talos clusters that need standalone ingress-nginx.
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# For Talos clusters, ingress-nginx is deployed via nixhelm.
{ config, lib, charts, ... }:
let
  # Ingress-nginx is managed by idpBuilder in KIND
  # Only enable for Talos or other environments where manual deployment is needed
  isTalos = config.environmentType == "talos";
  namespace = "ingress-nginx";
in
{
  # Only deploy ingress-nginx on Talos (KIND gets it from idpBuilder)
  config = lib.mkIf isTalos {
    applications.ingress-nginx = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-100";  # Early, after CRDs
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
      helm.releases.ingress-nginx = {
        chart = charts.kubernetes-ingress-nginx.ingress-nginx;
        values = {
          controller = {
            hostNetwork = true;  # For Talos bare-metal
            hostPort = {
              enabled = true;
            };
            replicaCount = 1;
            service = {
              type = "LoadBalancer";
            };
            ingressClassResource = {
              name = "nginx";
              enabled = true;
              default = true;
            };
          };
        };
      };
    };
  };
}
