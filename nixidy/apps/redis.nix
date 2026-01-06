# Redis application - In-cluster caching layer
# Mirrors: cdk8s/charts/apps/redis-chart.ts
{ config, lib, ... }:
let
  namespace = "nextjs";
  replicas = 1;  # Default for local dev
in
{
  applications.redis = {
    inherit namespace;
    createNamespace = false;  # postgres app owns nextjs namespace (sync-wave 50)

    # Sync wave for cache layer (after database)
    annotations = {
      "argocd.argoproj.io/sync-wave" = "60";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
        applyOutOfSyncOnly = true;  # Skip unchanged resources
      };
    };

    resources = {
      # Redis Deployment
      deployments.redis-deployment = {
        metadata = {
          inherit namespace;
          annotations = {
            "argocd.argoproj.io/sync-wave" = "60";
          };
          labels = {
            "app.kubernetes.io/component" = "cache";
            "app.kubernetes.io/part-of" = "data-layer";
            "app.kubernetes.io/name" = "redis";
          };
        };
        spec = {
          inherit replicas;
          selector.matchLabels.app = "redis";

          template = {
            metadata.labels.app = "redis";

            spec.containers = [{
              name = "redis";
              image = "redis:7-alpine";
              imagePullPolicy = "IfNotPresent";
              ports = [{ containerPort = 6379; }];

              resources = {
                requests = {
                  cpu = "50m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "256Mi";
                };
              };

              livenessProbe = {
                tcpSocket.port = 6379;
                initialDelaySeconds = 30;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 3;
              };

              readinessProbe = {
                exec.command = [ "redis-cli" "ping" ];
                initialDelaySeconds = 5;
                periodSeconds = 5;
                timeoutSeconds = 3;
                successThreshold = 1;
                failureThreshold = 3;
              };

              startupProbe = {
                tcpSocket.port = 6379;
                initialDelaySeconds = 0;
                periodSeconds = 10;
                timeoutSeconds = 5;
                successThreshold = 1;
                failureThreshold = 30;
              };
            }];
          };
        };
      };

      # Redis Service
      services.redis-service = {
        metadata = {
          inherit namespace;
        };
        spec = {
          selector.app = "redis";
          ports = [{
            port = 6379;
            targetPort = 6379;
          }];
        };
      };
    };
  };
}
