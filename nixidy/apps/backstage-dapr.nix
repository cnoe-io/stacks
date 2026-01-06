# Backstage Dapr Configuration
# Provides Dapr Configuration and State Store components for Backstage
# Enables Backstage to read/write configuration via Dapr Configuration API
# See: https://docs.dapr.io/developing-applications/building-blocks/configuration/howto-manage-configuration/
{ config, lib, ... }:
let
  backstageNamespace = "backstage";

  # Redis service in dapr-agents namespace - reuse existing infrastructure
  redisHost = "redis-service.dapr-agents.svc.cluster.local:6379";
in
{
  # Dapr Components for Backstage Configuration
  applications.backstage-dapr-components = {
    namespace = backstageNamespace;
    createNamespace = false;  # Backstage namespace created by backstage.nix

    annotations = {
      # Deploy after backstage namespace and dapr-runtime but before backstage app
      "argocd.argoproj.io/sync-wave" = "50";
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

    yamls = [
      # Dapr Configuration Store Component (read-only configuration)
      # Applications use GET /v1.0/configuration/{store-name} to read config
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Component
        metadata:
          name: configstore
          namespace: ${backstageNamespace}
        spec:
          type: configuration.redis
          version: v1
          metadata:
            - name: redisHost
              value: ${redisHost}
            - name: redisPassword
              value: ""
      ''

      # Dapr State Store Component (for writing configuration)
      # Dapr Configuration API is read-only, so we use State Store for writes
      # The key format matches configuration keys for consistency
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Component
        metadata:
          name: configstatestore
          namespace: ${backstageNamespace}
        spec:
          type: state.redis
          version: v1
          metadata:
            - name: redisHost
              value: ${redisHost}
            - name: redisPassword
              value: ""
            - name: keyPrefix
              value: "config"
      ''

      # Dapr Configuration for Backstage app
      # Enables tracing and sets app-specific settings
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Configuration
        metadata:
          name: backstage-dapr-config
          namespace: ${backstageNamespace}
        spec:
          tracing:
            samplingRate: "1"
            zipkin:
              endpointAddress: http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans
          features:
            - name: ServiceInvocation
              enabled: true
            - name: Configuration
              enabled: true
            - name: StateStore
              enabled: true
      ''
    ];
  };
}
