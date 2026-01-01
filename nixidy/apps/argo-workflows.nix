# Argo Workflows - Workflow Engine
# Provides workflow orchestration for CI/CD and batch processing.
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# Mirrors: cdk8s Argo Workflows configurations
{ config, lib, charts, ... }:
let
  namespace = "argo";
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

      # Use nixhelm for pre-rendered Helm chart
      helm.releases.argo-workflows = {
        chart = charts.argoproj.argo-workflows;
        values = {
          controller = {
            workflowNamespaces = [ namespace ];
          };
          server = {
            serviceType = "ClusterIP";
            extraArgs = [
              "--auth-mode=server"
            ];
          };
          workflow = {
            serviceAccount = {
              create = true;
            };
          };
        };
      };
    };
  };
}
