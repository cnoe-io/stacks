# Kargo Pipelines - Progressive Delivery Pipelines
# Defines Kargo Projects, Warehouses, and Stages for application promotion.
#
# Mirrors: cdk8s/charts/pipelines/
{ config, lib, ... }:
let
  namespace = "kargo-pipelines";
  inherit (config.cluster) ingressHost ingressPort;
  inherit (config.gitea) serviceName internalPort defaultOwner;
  giteaNamespace = config.gitea.namespace;
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";
  giteaInternalUrl = "http://${serviceName}.${giteaNamespace}.svc.cluster.local:${toString internalPort}";
  giteaExternalHost = "gitea.${ingressHost}${portSuffix}";
  giteaExternalUrl = "https://${giteaExternalHost}";
  # OCI registries normalize repository paths to lowercase
  defaultOwnerLower = lib.toLower defaultOwner;
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
        # =========================================================================
        # PreSync Hook - Wait for Kargo webhook server readiness
        # Prevents race condition where CRDs are applied before webhook is ready
        # =========================================================================
        ''
          apiVersion: batch/v1
          kind: Job
          metadata:
            name: wait-kargo-webhook
            namespace: ${namespace}
            annotations:
              argocd.argoproj.io/hook: PreSync
              argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
            labels:
              app.kubernetes.io/name: wait-kargo-webhook
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: presync-hook
          spec:
            backoffLimit: 10
            ttlSecondsAfterFinished: 300
            template:
              spec:
                restartPolicy: OnFailure
                containers:
                  - name: wait-webhook
                    image: curlimages/curl:8.5.0
                    command:
                      - /bin/sh
                      - -c
                      - |
                        echo "Waiting for Kargo webhook server to be ready..."
                        WEBHOOK_URL="https://kargo-webhooks-server.kargo.svc:443/healthz"
                        MAX_ATTEMPTS=60
                        ATTEMPT=0

                        while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
                          ATTEMPT=$((ATTEMPT + 1))
                          echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Checking $WEBHOOK_URL"

                          # Check if webhook server responds (ignore cert validation for internal traffic)
                          if curl -sk --connect-timeout 5 --max-time 10 "$WEBHOOK_URL" >/dev/null 2>&1; then
                            echo "Kargo webhook server is ready!"
                            exit 0
                          fi

                          echo "Webhook not ready, waiting 5s..."
                          sleep 5
                        done

                        echo "ERROR: Kargo webhook server not ready after $MAX_ATTEMPTS attempts"
                        exit 1
                    resources:
                      requests:
                        cpu: 10m
                        memory: 16Mi
                      limits:
                        cpu: 50m
                        memory: 32Mi
        ''
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
              # Backstage stages (Common Case pattern with config repo)
              - stageSelector:
                  name: backstage-dev
                autoPromotionEnabled: true
              - stageSelector:
                  name: backstage-staging
                autoPromotionEnabled: false
              # Legacy backstage stage (will be removed after migration)
              - stageSelector:
                  name: backstage
                autoPromotionEnabled: true
              # Other application stages
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
            # NOTE: Project-scoped webhookReceivers commented out in favor of cluster-scoped ClusterConfig
            # ClusterConfig (defined in kargo.nix) triggers ALL Warehouses across ALL projects,
            # which is the best practice when all repos are in the same Git org (Gitea).
            # See: https://docs.kargo.io/references/cluster-config/#webhookreceivers
            #
            # webhookReceivers:
            #   - name: gitea-webhook
            #     gitea:
            #       secretRef:
            #         name: kargo-gitea-webhook-secret
        ''
        # NOTE: Project-scoped webhook secret commented out - using cluster-scoped secret instead
        # The cluster-scoped secret is in kargo-cluster-secrets namespace (defined in kargo.nix)
        #
        # ''
        #   apiVersion: v1
        #   kind: Secret
        #   type: Opaque
        #   metadata:
        #     name: kargo-gitea-webhook-secret
        #     namespace: kargo-pipelines
        #     labels:
        #       app.kubernetes.io/name: kargo-gitea-webhook-secret
        #       app.kubernetes.io/part-of: kargo-pipelines
        #       kargo.akuity.io/cred-type: generic
        #   stringData:
        #     # Shared secret for webhook signature verification
        #     # Using a deterministic value based on cluster name for idempotency
        #     secret: kargo-gitea-webhook-thinkpad-secret-2024
        # ''
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
        # =========================================================================
        # PreSync Hook - Wait for Kargo webhook server readiness
        # This app creates Warehouse/Stage CRDs that require Kargo webhook
        # NOTE: Runs in 'kargo' namespace (not kargo-pipelines) because the
        # kargo-pipelines namespace may not exist yet when PreSync runs
        # =========================================================================
        ''
          apiVersion: batch/v1
          kind: Job
          metadata:
            name: wait-kargo-webhook-pipeline
            namespace: kargo
            annotations:
              argocd.argoproj.io/hook: PreSync
              argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
            labels:
              app.kubernetes.io/name: wait-kargo-webhook-pipeline
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: presync-hook
          spec:
            backoffLimit: 10
            ttlSecondsAfterFinished: 300
            template:
              spec:
                restartPolicy: OnFailure
                containers:
                  - name: wait-webhook
                    image: curlimages/curl:8.5.0
                    command:
                      - /bin/sh
                      - -c
                      - |
                        echo "Waiting for Kargo webhook server to be ready..."
                        WEBHOOK_URL="https://kargo-webhooks-server.kargo.svc:443/healthz"
                        MAX_ATTEMPTS=60
                        ATTEMPT=0

                        while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
                          ATTEMPT=$((ATTEMPT + 1))
                          echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Checking $WEBHOOK_URL"

                          if curl -sk --connect-timeout 5 --max-time 10 "$WEBHOOK_URL" >/dev/null 2>&1; then
                            echo "Kargo webhook server is ready!"
                            exit 0
                          fi

                          echo "Webhook not ready, waiting 5s..."
                          sleep 5
                        done

                        echo "ERROR: Kargo webhook server not ready after $MAX_ATTEMPTS attempts"
                        exit 1
                    resources:
                      requests:
                        cpu: 10m
                        memory: 16Mi
                      limits:
                        cpu: 50m
                        memory: 32Mi
        ''
        # =========================================================================
        # Warehouse - Backstage "Common Case" Pattern
        # Subscribes to BOTH Git (config repo) and Image (GHCR)
        # Creates Freight when either config changes or new images are pushed
        # =========================================================================
        ''
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
              # Git subscription for config changes (backstage-config repo)
              - git:
                  repoURL: https://github.com/PittampalliOrg/backstage-config.git
                  branch: main
                  # Watch base and overlay changes, ignore rendered output
                  includePaths:
                    - base/**
                    - overlays/**
                  excludePaths:
                    - rendered/**
              # Image subscription for new releases from GHCR
              - image:
                  repoURL: ghcr.io/pittampalliorg/backstage
                  imageSelectionStrategy: SemVer
                  allowTags: ^v?[0-9]+\.[0-9]+\.[0-9]+([\+-].*)?$
                  discoveryLimit: 20
        ''
        # =========================================================================
        # Stage - Backstage Dev
        # Auto-promotes from Warehouse, renders manifests with Kustomize
        # =========================================================================
        ''
          apiVersion: kargo.akuity.io/v1alpha1
          kind: Stage
          metadata:
            name: backstage-dev
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: backstage-dev-stage
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: stage
            annotations:
              kargo.akuity.io/color: blue
          spec:
            requestedFreight:
              - origin:
                  kind: Warehouse
                  name: backstage
                sources:
                  direct: true
            promotionTemplate:
              spec:
                vars:
                  - name: gitRepoURL
                    value: https://github.com/PittampalliOrg/backstage-config.git
                  - name: imageRepoURL
                    value: ghcr.io/pittampalliorg/backstage
                  - name: overlayPath
                    value: overlays/dev
                  - name: argoAppName
                    value: backstage-dev
                steps:
                  # Clone config repo: main branch for source, stage/dev for output
                  - uses: git-clone
                    as: clone-repo
                    config:
                      repoURL: ''${{ vars.gitRepoURL }}
                      checkout:
                        - branch: main
                          path: ./src
                        - branch: stage/dev
                          create: true
                          path: ./out
                  # Clear the output directory
                  - uses: git-clear
                    as: clear-output
                    config:
                      path: ./out
                  # Update image tag in kustomization.yaml
                  - uses: kustomize-set-image
                    as: update-image
                    config:
                      path: ./src/''${{ vars.overlayPath }}
                      images:
                        - image: ''${{ vars.imageRepoURL }}
                          tag: ''${{ imageFrom(vars.imageRepoURL).Tag }}
                  # Render manifests with kustomize build
                  - uses: kustomize-build
                    as: render-manifests
                    config:
                      path: ./src/''${{ vars.overlayPath }}
                      outPath: ./out/manifests/
                  # Commit rendered manifests
                  - uses: git-commit
                    as: commit-changes
                    config:
                      path: ./out
                      message: |
                        chore(dev): update backstage to ''${{ imageFrom(vars.imageRepoURL).Tag }}

                        Image: ''${{ vars.imageRepoURL }}:''${{ imageFrom(vars.imageRepoURL).Tag }}
                        Freight: ''${{ ctx.freight.alias }}
                  # Push to stage/dev branch
                  - uses: git-push
                    as: push-changes
                    config:
                      path: ./out
                  # Sync ArgoCD Application
                  - uses: argocd-update
                    as: sync-argocd
                    config:
                      apps:
                        - name: ''${{ vars.argoAppName }}
                          namespace: argocd
                          sources:
                            - repoURL: ''${{ vars.gitRepoURL }}
                              desiredRevision: ''${{ outputs['push-changes'].commit }}
        ''
        # =========================================================================
        # Stage - Backstage Staging
        # Manual promotion from dev stage
        # =========================================================================
        ''
          apiVersion: kargo.akuity.io/v1alpha1
          kind: Stage
          metadata:
            name: backstage-staging
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: backstage-staging-stage
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: stage
            annotations:
              kargo.akuity.io/color: yellow
          spec:
            requestedFreight:
              - origin:
                  kind: Warehouse
                  name: backstage
                sources:
                  stages:
                    - backstage-dev
            promotionTemplate:
              spec:
                vars:
                  - name: gitRepoURL
                    value: https://github.com/PittampalliOrg/backstage-config.git
                  - name: imageRepoURL
                    value: ghcr.io/pittampalliorg/backstage
                  - name: overlayPath
                    value: overlays/staging
                  - name: argoAppName
                    value: backstage-staging
                steps:
                  - uses: git-clone
                    as: clone-repo
                    config:
                      repoURL: ''${{ vars.gitRepoURL }}
                      checkout:
                        - branch: main
                          path: ./src
                        - branch: stage/staging
                          create: true
                          path: ./out
                  - uses: git-clear
                    as: clear-output
                    config:
                      path: ./out
                  - uses: kustomize-set-image
                    as: update-image
                    config:
                      path: ./src/''${{ vars.overlayPath }}
                      images:
                        - image: ''${{ vars.imageRepoURL }}
                          tag: ''${{ imageFrom(vars.imageRepoURL).Tag }}
                  - uses: kustomize-build
                    as: render-manifests
                    config:
                      path: ./src/''${{ vars.overlayPath }}
                      outPath: ./out/manifests/
                  - uses: git-commit
                    as: commit-changes
                    config:
                      path: ./out
                      message: |
                        chore(staging): update backstage to ''${{ imageFrom(vars.imageRepoURL).Tag }}

                        Promoted from: dev
                        Image: ''${{ vars.imageRepoURL }}:''${{ imageFrom(vars.imageRepoURL).Tag }}
                        Freight: ''${{ ctx.freight.alias }}
                  - uses: git-push
                    as: push-changes
                    config:
                      path: ./out
                  - uses: argocd-update
                    as: sync-argocd
                    config:
                      apps:
                        - name: ''${{ vars.argoAppName }}
                          namespace: argocd
                          sources:
                            - repoURL: ''${{ vars.gitRepoURL }}
                              desiredRevision: ''${{ outputs['push-changes'].commit }}
        ''
        # =========================================================================
        # ArgoCD Application - Backstage Dev
        # Points to stage/dev branch in config repo
        # =========================================================================
        ''
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: backstage-dev
            namespace: argocd
            labels:
              app.kubernetes.io/name: backstage-dev
              app.kubernetes.io/part-of: kargo-pipelines
            annotations:
              argocd.argoproj.io/sync-wave: "100"
              kargo.akuity.io/authorized-stage: ${namespace}:backstage-dev
          spec:
            project: default
            destination:
              namespace: backstage-dev
              server: https://kubernetes.default.svc
            source:
              repoURL: https://github.com/PittampalliOrg/backstage-config.git
              targetRevision: stage/dev
              path: manifests
            syncPolicy:
              automated:
                prune: true
                selfHeal: true
              syncOptions:
                - ServerSideApply=true
                - CreateNamespace=false
        ''
        # =========================================================================
        # ArgoCD Application - Backstage Staging
        # Points to stage/staging branch in config repo
        # =========================================================================
        ''
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: backstage-staging
            namespace: argocd
            labels:
              app.kubernetes.io/name: backstage-staging
              app.kubernetes.io/part-of: kargo-pipelines
            annotations:
              argocd.argoproj.io/sync-wave: "100"
              kargo.akuity.io/authorized-stage: ${namespace}:backstage-staging
          spec:
            project: default
            destination:
              namespace: backstage-staging
              server: https://kubernetes.default.svc
            source:
              repoURL: https://github.com/PittampalliOrg/backstage-config.git
              targetRevision: stage/staging
              path: manifests
            syncPolicy:
              automated:
                prune: true
                selfHeal: true
              syncOptions:
                - ServerSideApply=true
                - CreateNamespace=false
        ''
      ];
    };
  };
}
