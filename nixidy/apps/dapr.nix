# Dapr Agents Applications
# CRDs, runtime, Redis, components, and SpecKit agents
# Mirrors: cdk8s/charts/platform/dapr-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  daprSystemNamespace = "dapr-system";
  daprAgentsNamespace = "dapr-agents";
in
{
  # Dapr CRDs - placeholder for Helm deployment
  applications.dapr-crds = {
    namespace = "default";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-200";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
        replace = true;
      };
    };

    yamls = [
      ''
        # Dapr CRDs - Deployed via ArgoCD Application with Helm source
        # Chart: dapr from https://dapr.github.io/helm-charts
        # Version: 1.16.3
        # Values: Only CRDs (all operators disabled)
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: dapr-crds-placeholder
          namespace: default
        data:
          note: "CRDs deployed via Helm chart in ArgoCD"
      ''
    ];
  };

  # Dapr Runtime (Control Plane) - placeholder for Helm deployment
  applications.dapr-runtime = {
    namespace = daprSystemNamespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-120";
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

    yamls = [
      ''
        # Dapr Runtime - Deployed via ArgoCD Application with Helm source
        # Chart: dapr from https://dapr.github.io/helm-charts
        # Version: 1.16.3
        # Values:
        #   global.ha.enabled: false
        #   global.mtls.enabled: true
        #   global.logAsJson: true
        #   dapr_dashboard.enabled: true
        apiVersion: v1
        kind: Namespace
        metadata:
          name: ${daprSystemNamespace}
          labels:
            app.kubernetes.io/managed-by: nixidy
            app.kubernetes.io/component: dapr
            app.kubernetes.io/part-of: platform
      ''
    ];
  };

  # Dapr Agents Redis - State and Pub/Sub backend
  applications.dapr-agents-redis = {
    namespace = daprAgentsNamespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-100";
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
      namespaces.${daprAgentsNamespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "agents";
          "app.kubernetes.io/part-of" = "dapr-agents";
        };
      };

      deployments.redis = {
        metadata = {
          namespace = daprAgentsNamespace;
          labels.app = "redis";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "redis";

          template = {
            metadata.labels.app = "redis";

            spec.containers = [{
              name = "redis";
              image = "redis:7-alpine";
              ports = [{
                containerPort = 6379;
                name = "redis";
              }];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  memory = "256Mi";
                };
              };
            }];
          };
        };
      };

      services.redis-service = {
        metadata = {
          namespace = daprAgentsNamespace;
          labels.app = "redis";
        };
        spec = {
          ports = [{
            name = "redis";
            port = 6379;
            targetPort = "redis";
          }];
          selector.app = "redis";
        };
      };
    };
  };

  # Dapr Agents Secrets
  applications.dapr-agents-secrets = {
    namespace = daprAgentsNamespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-95";
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
        limit = 10;
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
          name: dapr-agents-llm-providers
          namespace: ${daprAgentsNamespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: dapr-agents-llm-providers
            creationPolicy: Owner
          data:
            - secretKey: ANTHROPIC_API_KEY
              remoteRef:
                key: ANTHROPIC-API-KEY
            - secretKey: OPENAI_API_KEY
              remoteRef:
                key: OPENAI-API-KEY
      ''
    ];
  };

  # Dapr Components (State stores, Pub/Sub, Conversation)
  applications.dapr-components = {
    namespace = daprAgentsNamespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-90";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    yamls = [
      # Pub/Sub Component
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Component
        metadata:
          name: messagepubsub
          namespace: ${daprAgentsNamespace}
        spec:
          type: pubsub.redis
          version: v1
          metadata:
            - name: redisHost
              value: redis-service.${daprAgentsNamespace}.svc.cluster.local:6379
            - name: redisPassword
              value: ""
      ''
      # Workflow State Store
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Component
        metadata:
          name: workflowstatestore
          namespace: ${daprAgentsNamespace}
        spec:
          type: state.redis
          version: v1
          metadata:
            - name: redisHost
              value: redis-service.${daprAgentsNamespace}.svc.cluster.local:6379
            - name: redisPassword
              value: ""
            - name: actorStateStore
              value: "true"
      ''
      # Agent Registry Store
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Component
        metadata:
          name: agentregistrystore
          namespace: ${daprAgentsNamespace}
        spec:
          type: state.redis
          version: v1
          metadata:
            - name: redisHost
              value: redis-service.${daprAgentsNamespace}.svc.cluster.local:6379
            - name: redisPassword
              value: ""
      ''
      # Memory Store
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Component
        metadata:
          name: memorystore
          namespace: ${daprAgentsNamespace}
        spec:
          type: state.redis
          version: v1
          metadata:
            - name: redisHost
              value: redis-service.${daprAgentsNamespace}.svc.cluster.local:6379
            - name: redisPassword
              value: ""
      ''
      # Anthropic Conversation Component
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Component
        metadata:
          name: anthropic
          namespace: ${daprAgentsNamespace}
        spec:
          type: conversation.anthropic
          version: v1
          metadata:
            - name: key
              secretKeyRef:
                name: dapr-agents-llm-providers
                key: ANTHROPIC_API_KEY
            - name: model
              value: claude-opus-4-5-20251101
            - name: cacheTTL
              value: 10m
      ''
      # Dapr Tracing Configuration
      ''
        apiVersion: dapr.io/v1alpha1
        kind: Configuration
        metadata:
          name: speckit-tracing
          namespace: ${daprAgentsNamespace}
        spec:
          tracing:
            samplingRate: "1"
            zipkin:
              endpointAddress: http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans
      ''
    ];
  };

  # SpecKit Agents RBAC
  applications.speckit-agents-rbac = {
    namespace = daprAgentsNamespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-80";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      serviceAccounts.speckit-agents = {
        metadata.namespace = daprAgentsNamespace;
      };

      roles.speckit-agents-role = {
        metadata.namespace = daprAgentsNamespace;
        rules = [
          {
            apiGroups = [ "" "apps" "batch" ];
            resources = [ "pods" "services" "deployments" "jobs" "configmaps" "secrets" ];
            verbs = [ "get" "list" "watch" "create" "update" "patch" "delete" ];
          }
          {
            apiGroups = [ "dapr.io" ];
            resources = [ "components" "configurations" "subscriptions" ];
            verbs = [ "get" "list" "watch" ];
          }
        ];
      };

      roleBindings.speckit-agents-rolebinding = {
        metadata.namespace = daprAgentsNamespace;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "speckit-agents-role";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "speckit-agents";
          namespace = daprAgentsNamespace;
        }];
      };
    };
  };
}
