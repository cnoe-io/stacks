# Argo Workflows - Workflow Engine
# Provides workflow orchestration for CI/CD and batch processing.
#
# Mirrors: cdk8s Argo Workflows configurations
{ config, lib, ... }:
let
  namespace = "argo-workflows";
in
{
  config = {
    applications.argo-workflows = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "50";
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

      # Placeholder for Argo Workflows deployment
      # Chart: argo-workflows from https://argoproj.github.io/argo-helm
      yamls = [
        ''
          # Argo Workflows workflow engine
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Key values:
          # - controller.workflowNamespaces for multi-tenant
          # - server.extraArgs for SSO
          # - persistence for artifact storage
        ''
      ];
    };
  };
}
