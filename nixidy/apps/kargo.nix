# Kargo - Progressive Delivery
# Provides GitOps-based progressive delivery for Kubernetes.
#
# NOTE: Kargo uses OCI registry (ghcr.io/akuity/kargo-charts) which nixidy doesn't support.
# We use ArgoCD Application with OCI Helm source - ArgoCD handles OCI natively.
# See: https://nixidy.dev/user_guide/helm_charts/
#
# Mirrors: cdk8s/config/applications.ts kargo entries
{ config, lib, ... }:
let
  namespace = "kargo";
in
{
  config = {
    # Kargo Secrets
    applications.kargo-secrets = lib.mkIf (config.environmentType == "talos") {
      inherit namespace;
      createNamespace = true;

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
          createNamespace = true;
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
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: kargo-admin-credentials
            namespace: ${namespace}
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: kargo-admin-credentials
              creationPolicy: Owner
            data:
              - secretKey: ADMIN_ACCOUNT_PASSWORD
                remoteRef:
                  key: kargo-admin-password
        ''
      ];
    };

    # NOTE: Manual kargo-webhooks-cert is no longer needed
    # cert-manager now handles TLS certificate generation for Kargo webhooks
    # See certificates.enabled: true in kargo-helm values below

    # Kargo application - via ArgoCD OCI Helm Application
    applications.kargo = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "65";
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

      # Use ArgoCD Application with OCI Helm source (nixidy doesn't support OCI)
      yamls = [
        ''
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: kargo-helm
            namespace: argocd
            annotations:
              argocd.argoproj.io/sync-wave: "65"
          spec:
            project: default
            destination:
              server: https://kubernetes.default.svc
              namespace: ${namespace}
            source:
              repoURL: ghcr.io/akuity/kargo-charts
              chart: kargo
              targetRevision: 1.8.4
              helm:
                valuesObject:
                  api:
                    host: kargo.cnoe.localtest.me
                    adminAccount:
                      enabled: true
                      passwordHash: "$2b$10$bqVe5nszNR1eEt20jtNSle24cBsnhiiNcFHgZuMcv7HACZCD6a3IW"
                      tokenSigningKey: "pw4J0w4L2sMcvsbdWNPgWSeOuBm1IK0b"
                      tokenTTL: "24h"
                    service:
                      type: ClusterIP
                      port: 8080
                    grpcWeb: true
                    logLevel: INFO
                    tls:
                      enabled: false
                    ingress:
                      enabled: true
                      className: nginx
                      annotations:
                        nginx.ingress.kubernetes.io/backend-protocol: HTTP
                        nginx.ingress.kubernetes.io/grpc-backend: "true"
                      tls:
                        enabled: false
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        cpu: 500m
                        memory: 256Mi
                  controller:
                    logLevel: INFO
                    # Allow credentials over HTTP for internal gitea service
                    allowCredentialsOverHTTP: true
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        cpu: 500m
                        memory: 512Mi
                  # Webhooks enabled with cert-manager for TLS (required for PromotionTask)
                  # cert-manager generates certificates and injects CA bundle into MutatingWebhookConfiguration
                  webhooksServer:
                    enabled: true
                    tls:
                      selfSignedCert: true
                  webhooks:
                    register: true
                    logLevel: INFO
                    resources:
                      requests:
                        cpu: 100m
                        memory: 128Mi
                      limits:
                        cpu: 200m
                        memory: 256Mi
                  management:
                    logLevel: INFO
                    resources:
                      requests:
                        cpu: 50m
                        memory: 64Mi
                      limits:
                        cpu: 100m
                        memory: 128Mi
                  garbageCollector:
                    resources:
                      requests:
                        cpu: 50m
                        memory: 64Mi
                      limits:
                        cpu: 100m
                        memory: 128Mi
                  externalWebhooksServer:
                    enabled: true
                    tls:
                      enabled: false
                    incomingWebhooks:
                      github:
                        enabled: true
                        secretKeyRef:
                          name: kargo-github-webhook-secret
                          key: secret
                  awsLoadBalancerController:
                    enabled: false
                  rbac:
                    installClusterRoles: true
                    installClusterRoleBindings: true
                  # cert-manager integration for webhook TLS
                  certificates:
                    enabled: true
            syncPolicy:
              automated:
                prune: true
                selfHeal: true
              syncOptions:
                - CreateNamespace=true
                - ServerSideApply=true
        ''
      ];
    };

    # =========================================================================
    # Kargo ClusterConfig - Cluster-scoped webhook receivers
    # Best practice: Use ClusterConfig when all repos are in the same Git org
    # This triggers ALL applicable Warehouses across ALL projects
    # =========================================================================
    applications.kargo-cluster-config = lib.mkIf (config.environmentType == "kind") {
      namespace = "kargo";
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "65";
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
        # Namespace for cluster-scoped secrets (required by Kargo)
        ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: kargo-cluster-secrets
            labels:
              app.kubernetes.io/name: kargo-cluster-secrets
              app.kubernetes.io/part-of: kargo
        ''
        # Cluster-scoped webhook secret
        # Referenced by ClusterConfig, must be in kargo-cluster-secrets namespace
        ''
          apiVersion: v1
          kind: Secret
          type: Opaque
          metadata:
            name: kargo-gitea-cluster-webhook-secret
            namespace: kargo-cluster-secrets
            labels:
              app.kubernetes.io/name: kargo-gitea-cluster-webhook-secret
              app.kubernetes.io/part-of: kargo
              kargo.akuity.io/cred-type: generic
          stringData:
            secret: kargo-gitea-webhook-thinkpad-secret-2024
        ''
        # ClusterConfig - cluster-scoped webhook receiver
        # Triggers artifact discovery for ALL Warehouses across ALL projects
        ''
          apiVersion: kargo.akuity.io/v1alpha1
          kind: ClusterConfig
          metadata:
            name: cluster
          spec:
            webhookReceivers:
              - name: gitea-cluster-webhook
                gitea:
                  secretRef:
                    name: kargo-gitea-cluster-webhook-secret
        ''
      ];
    };
  };
}
