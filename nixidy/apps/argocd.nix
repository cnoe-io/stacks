# ArgoCD Configuration - Disabled by default
# IDPBuilder manages ArgoCD directly. This app can be enabled for custom configuration.
# For custom ArgoCD ConfigMap overrides, use:
# idpbuilder create -c argocd:/path/to/argocd-cm-override.yaml
# See: https://cnoe.io/docs/idpbuilder/override
#
# Mirrors: cdk8s/charts/platform/argocd-config-chart.ts
{ config, lib, ... }:
let
  # ArgoCD configuration is typically managed by idpBuilder
  # Only enable this for custom health checks or configuration
  enableArgocdConfig = false;
  namespace = "argocd";
in
{
  # ArgoCD configuration is disabled by default since idpBuilder manages ArgoCD
  config = lib.mkIf enableArgocdConfig {
    applications.argocd-config = {
      inherit namespace;
      createNamespace = false;  # argocd namespace already exists

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-110";  # Apply very early
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          serverSideApply = true;
        };
      };

      resources = {
        # Example: Custom health check for Ingress resources
        # Uncomment and modify as needed
        # configMaps.argocd-cm = {
        #   metadata = {
        #     inherit namespace;
        #     labels = {
        #       "app.kubernetes.io/component" = "config";
        #       "app.kubernetes.io/part-of" = "argocd";
        #       "app.kubernetes.io/name" = "argocd-cm";
        #     };
        #   };
        #   data = {
        #     "resource.customizations.health.networking.k8s.io_Ingress" = ''
        #       hs = {}
        #       hs.status = "Healthy"
        #       hs.message = "Ingress is always considered healthy"
        #       return hs
        #     '';
        #   };
        # };
      };
    };
  };
}
