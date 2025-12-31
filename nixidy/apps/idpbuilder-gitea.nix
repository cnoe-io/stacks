# idpBuilder Gitea configuration - KIND only
# This app is only deployed in KIND (local development) where idpBuilder manages Gitea
# Mirrors: cdk8s/charts/infra/idpbuilder-gitea-chart.ts
{ config, lib, ... }:
let
  # Only include for kind environment
  isKind = config.environmentType == "kind";
  namespace = "gitea";
in
{
  # Conditionally include this application based on environment type
  config = lib.mkIf isKind {
    applications.idpbuilder-gitea = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-80";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
        };
      };

      resources = {
        # Namespace for Gitea
        namespaces.${namespace} = {
          metadata.labels = {
            "app.kubernetes.io/managed-by" = "nixidy";
            "app.kubernetes.io/component" = "git-server";
            "app.kubernetes.io/part-of" = "developer-platform";
          };
        };

        # ConfigMap with Gitea webhook configuration for ArgoCD
        configMaps.gitea-webhook-config = {
          metadata.namespace = namespace;
          data = {
            "description" = "Gitea webhook configuration for ArgoCD notifications";
            "argocd-webhook-url" = "http://argocd-server.argocd.svc.cluster.local/api/webhook";
          };
        };
      };
    };
  };
}
