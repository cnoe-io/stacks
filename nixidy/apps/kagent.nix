# KAgent - AI Agent Platform
# Provides AI agent orchestration for Kubernetes.
#
# NOTE: kagent uses OCI registry (ghcr.io/kagent-dev/kagent) which nixidy doesn't support.
# We use ArgoCD Application with OCI Helm source - ArgoCD handles OCI natively.
#
# Mirrors: cdk8s/charts/infra/kagent-chart.ts
{ config, lib, ... }:
let
  namespace = "kagent";
  ingressHost = config.cluster.ingressHost;
  kagentVersion = "0.7.4";
in
{
  config = {
    # KAgent CRDs - via ArgoCD OCI Helm Application
    applications.kagent-crds = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-125";  # CRDs first
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = false;  # Never auto-delete CRDs
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
        };
      };

      yamls = [
        ''
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: kagent-crds-helm
            namespace: argocd
            annotations:
              argocd.argoproj.io/sync-wave: "-125"
          spec:
            project: default
            destination:
              server: https://kubernetes.default.svc
              namespace: ${namespace}
            source:
              repoURL: ghcr.io/kagent-dev/kagent/helm
              chart: kagent-crds
              targetRevision: ${kagentVersion}
            syncPolicy:
              automated:
                prune: false
                selfHeal: true
              syncOptions:
                - CreateNamespace=true
                - ServerSideApply=true
        ''
      ];
    };

    # KAgent application - via ArgoCD OCI Helm Application
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

      yamls = [
        ''
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: kagent-helm
            namespace: argocd
            annotations:
              argocd.argoproj.io/sync-wave: "75"
          spec:
            project: default
            destination:
              server: https://kubernetes.default.svc
              namespace: ${namespace}
            source:
              repoURL: ghcr.io/kagent-dev/kagent/helm
              chart: kagent
              targetRevision: ${kagentVersion}
              helm:
                valuesObject:
                  namespace: ${namespace}
                  controller:
                    replicas: 1
                    logLevel: info
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        memory: 1Gi
                  ui:
                    enabled: true
                    replicas: 1
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        memory: 512Mi
                  kmcp:
                    enabled: true
                  ingress:
                    enabled: true
                    className: nginx
                    hosts:
                      - host: kagent.${ingressHost}
                        paths:
                          - path: /
                            pathType: Prefix
            syncPolicy:
              automated:
                prune: true
                selfHeal: true
              syncOptions:
                - ServerSideApply=true
        ''
      ];
    };

    # KAgent Secrets - enabled for all environments with Azure Key Vault
    applications.kagent-secrets = {
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
        # kagent-openai - for promql-agent
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: kagent-openai
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: kagent-openai
              app.kubernetes.io/part-of: kagent
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: kagent-openai
              creationPolicy: Owner
            data:
              - secretKey: OPENAI_API_KEY
                remoteRef:
                  key: OPENAI-API-KEY
        ''
        # kagent-api-keys - combined API keys
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: kagent-api-keys
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: kagent-api-keys
              app.kubernetes.io/part-of: kagent
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
                  key: ANTHROPIC-API-KEY
              - secretKey: OPENAI_API_KEY
                remoteRef:
                  key: OPENAI-API-KEY
        ''
      ];
    };
  };
}
