# KAgent - AI Agent Platform
# Provides AI agent orchestration for Kubernetes.
#
# Mirrors: cdk8s/charts/infra/kagent-chart.ts
{ config, lib, ... }:
let
  namespace = "kagent";
in
{
  config = {
    # KAgent CRDs
    applications.kagent-crds = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "70";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = false;  # Don't prune CRDs
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
          replace = true;
        };
      };

      yamls = [
        ''
          # KAgent CRDs placeholder
          # Actual CRDs should be pulled from kagent releases
        ''
      ];
    };

    # KAgent application
    applications.kagent = {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "75";
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

      # Placeholder for KAgent deployment
      yamls = [
        ''
          # KAgent AI agent platform
          # Components:
          # - kagent-controller
          # - kagent-dashboard
          # - Agent resources (Agents, ModelConfigs, MCPServers)
        ''
      ];
    };

    # KAgent Secrets
    applications.kagent-secrets = lib.mkIf (config.environmentType == "talos") {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "72";
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
        retry = {
          limit = 5;
          backoff = {
            duration = "5s";
            factor = 2;
            maxDuration = "3m";
          };
        };
      };

      yamls = [
        ''
          apiVersion: external-secrets.io/v1beta1
          kind: ExternalSecret
          metadata:
            name: kagent-api-keys
            namespace: ${namespace}
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: kagent-api-keys
              creationPolicy: Owner
            data:
              - secretKey: ANTHROPIC_API_KEY
                remoteRef:
                  key: anthropic-api-key
              - secretKey: OPENAI_API_KEY
                remoteRef:
                  key: openai-api-key
        ''
      ];
    };
  };
}
