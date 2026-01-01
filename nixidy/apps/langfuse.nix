# Langfuse - LLM Observability and Tracing
# Provides observability for LLM applications with tracing, metrics, and logging.
#
# Mirrors: cdk8s/charts/infra/langfuse-chart.ts
{ config, lib, ... }:
let
  namespace = "langfuse";
in
{
  config = {
    # Langfuse namespace
    applications.langfuse-namespace = {
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
        };
      };

      resources = {
        namespaces.langfuse = {
          metadata = {
            name = namespace;
            labels = {
              "app.kubernetes.io/name" = "langfuse";
              "app.kubernetes.io/part-of" = "observability";
            };
          };
        };
      };
    };

    # Langfuse main application
    applications.langfuse = {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "55";
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

      # Placeholder ConfigMap until Langfuse is configured
      resources = {
        configMaps.langfuse-placeholder = {
          metadata = {
            namespace = namespace;
            labels = {
              "app.kubernetes.io/name" = "langfuse";
              "app.kubernetes.io/part-of" = "observability";
            };
          };
          data = {
            status = "placeholder";
            note = "Langfuse LLM observability. See cdk8s/charts/infra/langfuse-chart.ts";
          };
        };
      };
    };
  };
}
