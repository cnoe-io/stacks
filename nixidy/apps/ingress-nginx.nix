# Ingress NGINX Controller - Disabled by default
# IDPBuilder manages ingress-nginx directly in KIND clusters.
# This app can be enabled for Talos clusters that need standalone ingress-nginx.
#
# For Talos clusters, ingress-nginx is typically deployed via Helm.
# Nixidy uses yamls for inline manifests or helm.releases with nixhelm charts.
{ config, lib, ... }:
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

      # Ingress-NGINX deployment manifests
      # For production, consider using nixhelm with helm.releases
      # or pre-rendered Helm templates
      yamls = [
        ''
          # Placeholder: ingress-nginx would be deployed via Helm
          # Chart: ingress-nginx from https://kubernetes.github.io/ingress-nginx
          # Version: 4.10.0
          #
          # For full deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered Helm templates as yamls
          #
          # Example helm.releases usage (requires nixhelm):
          # helm.releases.ingress-nginx = {
          #   chart = charts.ingress-nginx;
          #   values = {
          #     controller.hostNetwork = true;
          #     controller.replicaCount = 1;
          #   };
          # };
        ''
      ];

      # Reference configuration (for documentation)
      # Helm values that would be used:
      # - controller.hostNetwork = true (for Talos bare-metal)
      # - controller.hostPort.enabled = true
      # - controller.service.type = "LoadBalancer" or "NodePort"
      # - controller.ingressClassResource.name = "nginx"
      # - controller.ingressClassResource.default = true
    };
  };
}
