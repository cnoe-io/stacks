# Kargo Pipelines - Progressive Delivery Pipelines
# Defines Kargo Projects, Warehouses, and Stages for application promotion.
#
# Mirrors: cdk8s/charts/pipelines/
{ config, lib, ... }:
let
  namespace = "kargo-pipelines";
in
{
  config = {
    # Kargo Pipelines Project
    applications.kargo-pipelines-project = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "70";
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
          apiVersion: kargo.akuity.io/v1alpha1
          kind: Project
          metadata:
            name: kargo-pipelines
          spec:
            promotionPolicies:
              - stage: dev
                autoPromotionEnabled: true
              - stage: staging
                autoPromotionEnabled: false
              - stage: prod
                autoPromotionEnabled: false
        ''
      ];
    };

    # Kargo Pipelines Credentials
    applications.kargo-pipelines-credentials = lib.mkIf (config.environmentType == "talos") {
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
            name: kargo-pipelines-credentials
            namespace: ${namespace}
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: kargo-pipelines-credentials
              creationPolicy: Owner
            data:
              - secretKey: GITHUB_TOKEN
                remoteRef:
                  key: github-token
        ''
      ];
    };

    # Backstage Pipeline example
    applications.kargo-backstage-pipeline = {
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
          # Kargo Warehouse for Backstage images
          apiVersion: kargo.akuity.io/v1alpha1
          kind: Warehouse
          metadata:
            name: backstage
            namespace: ${namespace}
          spec:
            subscriptions:
              - image:
                  repoURL: ghcr.io/pittampalliorg/backstage
                  semverConstraint: "*"
        ''
        ''
          # Kargo Stages for Backstage promotion
          # dev -> staging -> prod
          apiVersion: kargo.akuity.io/v1alpha1
          kind: Stage
          metadata:
            name: backstage-dev
            namespace: ${namespace}
          spec:
            subscriptions:
              warehouse: backstage
            promotionMechanisms:
              argoCDAppUpdates:
                - appName: backstage-dev
                  appNamespace: argocd
        ''
      ];
    };
  };
}
