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
      createNamespace = false;  # We create namespace manually with required labels

      resources = {
        namespaces.kargo-pipelines = {
          metadata.labels = {
            "app.kubernetes.io/name" = "kargo-pipelines";
            "app.kubernetes.io/part-of" = "kargo";
            "app.kubernetes.io/component" = "namespace";
            "kargo.akuity.io/project" = "true";
          };
        };
      };

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
            labels:
              app.kubernetes.io/name: kargo-pipelines
              app.kubernetes.io/part-of: kargo
              app.kubernetes.io/component: project
        ''
        ''
          apiVersion: kargo.akuity.io/v1alpha1
          kind: ProjectConfig
          metadata:
            name: kargo-pipelines
            namespace: kargo-pipelines
            labels:
              app.kubernetes.io/name: kargo-pipelines-config
              app.kubernetes.io/part-of: kargo
              app.kubernetes.io/component: project-config
          spec:
            promotionPolicies:
              - stageSelector:
                  name: "glob:*-local-dev"
                autoPromotionEnabled: true
              - stageSelector:
                  name: "glob:*-dev"
                autoPromotionEnabled: true
              - stageSelector:
                  name: "glob:*-staging"
                autoPromotionEnabled: false
              - stageSelector:
                  name: "glob:*-prod"
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
          apiVersion: external-secrets.io/v1
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
            labels:
              app.kubernetes.io/name: backstage-warehouse
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: warehouse
          spec:
            freightCreationPolicy: Automatic
            interval: 5m0s
            subscriptions:
              - image:
                  repoURL: ghcr.io/pittampalliorg/backstage
                  imageSelectionStrategy: SemVer
                  semverConstraint: "*"
                  discoveryLimit: 20
                  platform: linux/amd64
        ''
        ''
          # Kargo Stage for Backstage dev environment
          # Uses requestedFreight and promotionTemplate (Kargo 1.8.4 API)
          # Note: Stage name is backstage-dev, but syncs backstage-local-dev ArgoCD app
          apiVersion: kargo.akuity.io/v1alpha1
          kind: Stage
          metadata:
            name: backstage-dev
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: backstage-dev-stage
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: stage
          spec:
            requestedFreight:
              - origin:
                  kind: Warehouse
                  name: backstage
                sources:
                  direct: true
            promotionTemplate:
              spec:
                steps:
                  - uses: argocd-update
                    as: sync-argocd-app
                    config:
                      apps:
                        - name: backstage-local-dev
                          namespace: argocd
        ''
      ];
    };
  };
}
