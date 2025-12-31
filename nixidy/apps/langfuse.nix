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

      # Placeholder for Langfuse deployment
      # In production, use Helm or full manifest templates
      yamls = [
        ''
          # Langfuse observability platform
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Components:
          # - langfuse-server (web UI and API)
          # - langfuse-worker (background jobs)
          # - langfuse-postgres (database)
          # - langfuse-clickhouse (analytics)
          # - langfuse-redis (caching)
          # - langfuse-minio (object storage)
        ''
      ];
    };
  };
}
