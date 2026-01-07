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
              # Auto-promote backstage stage (primary deployment)
              - stageSelector:
                  name: backstage
                autoPromotionEnabled: true
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
        # =========================================================================
        ''
          apiVersion: batch/v1
          kind: Job
          metadata:
            name: wait-kargo-webhook-pipeline
            namespace: ${namespace}
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
        # PromotionTask - Reusable promotion steps for Backstage
        # Requires cert-manager for MutatingWebhookConfiguration TLS
        # =========================================================================
        ''
          apiVersion: kargo.akuity.io/v1alpha1
          kind: PromotionTask
          metadata:
            name: backstage-promote
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: backstage-promote
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: promotiontask
          spec:
            vars:
              - name: gitRepoURL
              - name: gitRepoURLExternal
              - name: imageRepoURL
              - name: baseImage
                value: ghcr.io/pittampalliorg/backstage
              - name: argoAppName
            steps:
              # Clone the Git repository containing manifests
              - uses: git-clone
                as: clone-repo
                config:
                  repoURL: ''${{ vars.gitRepoURL }}
                  checkout:
                    - branch: main
                      path: ./repo
              # Update the image in Deployment-backstage.yaml using yaml-update
              - uses: yaml-update
                as: update-image
                config:
                  path: ./repo/Deployment-backstage.yaml
                  updates:
                    - key: spec.template.spec.containers.0.image
                      value: ''${{ vars.imageRepoURL }}:''${{ imageFrom(vars.imageRepoURL).Tag }}
              # Commit the changes
              - uses: git-commit
                as: commit-changes
                config:
                  path: ./repo
                  message: "chore: update backstage image to ''${{ imageFrom(vars.imageRepoURL).Tag }}"
              # Push to the repository
              - uses: git-push
                as: push-changes
                config:
                  path: ./repo
              # Sync the ArgoCD application
              - uses: argocd-update
                as: sync-argocd-app
                config:
                  apps:
                    - name: ''${{ vars.argoAppName }}
                      namespace: argocd
                      sources:
                        - repoURL: ''${{ vars.gitRepoURLExternal }}
                          desiredRevision: ''${{ task.outputs['push-changes'].commit }}
        ''
        # =========================================================================
        # Warehouse - Backstage Image Discovery
        # Watches Gitea registry for new semver-tagged images
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
              # NOTE: Git subscription commented out to avoid duplicate Freight creation
              # Each (git commit + image) combination creates a Freight, and promotions
              # create new commits, causing a cascade of Freight items.
              # Uncomment if you need git-based triggering via webhooks.
              # - git:
              #     repoURL: https://gitea.cnoe.localtest.me:8443/giteaAdmin/idpbuilder-thinkpad-backstage-local-dev-manifests.git
              #     branch: main
              #     insecureSkipTLSVerify: true
              # Image subscription with semver filtering
              - image:
                  repoURL: gitea.cnoe.localtest.me:8443/giteaadmin/backstage
                  imageSelectionStrategy: SemVer
                  # Match semver tags: v1.0.0, 1.0.0, v1.0.0-rc1, etc.
                  allowTags: ^v?[0-9]+\.[0-9]+\.[0-9]+([\+-].*)?$
                  discoveryLimit: 20
                  platform: linux/amd64
                  insecureSkipTLSVerify: true
        ''
        # =========================================================================
        # Stage - Backstage
        # First stage in pipeline, receives freight directly from Warehouse
        # =========================================================================
        ''
          apiVersion: kargo.akuity.io/v1alpha1
          kind: Stage
          metadata:
            name: backstage
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: backstage-stage
              app.kubernetes.io/part-of: kargo-pipelines
              app.kubernetes.io/component: stage
            annotations:
              # Stage color for Kargo UI
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
                    value: http://my-gitea-http.gitea.svc.cluster.local:3000/giteaAdmin/idpbuilder-thinkpad-backstage-manifests.git
                  - name: gitRepoURLExternal
                    value: https://gitea.cnoe.localtest.me:8443/giteaAdmin/idpbuilder-thinkpad-backstage-manifests.git
                  - name: imageRepoURL
                    value: gitea.cnoe.localtest.me:8443/giteaadmin/backstage
                  - name: baseImage
                    value: ghcr.io/pittampalliorg/backstage
                  - name: argoAppName
                    value: backstage
                # NOTE: Kargo v1.8.4 MutatingWebhook Bug
                # The mutating webhook doesn't copy promotionTemplate.spec.steps from Stage to Promotion
                # when creating Promotions manually via kubectl/API.
                #
                # Behavior:
                # - Auto-promotions (created by Kargo controller) work correctly - steps are populated
                # - Manual promotions fail validation with "Stage defines no promotion steps"
                # - PromotionTask references also don't get inflated for manual promotions
                #
                # Workaround: Use inline steps (shown below). Auto-promotion handles this transparently.
                # For manual promotions, include spec.steps explicitly in the Promotion resource.
                # See: https://github.com/akuity/kargo/issues/4935
                steps:
                  # Clone the Git repository containing manifests
                  - uses: git-clone
                    as: clone-repo
                    config:
                      repoURL: ''${{ vars.gitRepoURL }}
                      checkout:
                        - branch: main
                          path: ./repo
                  # Update the image in Deployment-backstage.yaml using yaml-update
                  - uses: yaml-update
                    as: update-image
                    config:
                      path: ./repo/Deployment-backstage.yaml
                      updates:
                        - key: spec.template.spec.containers.0.image
                          value: ''${{ vars.imageRepoURL }}:''${{ imageFrom(vars.imageRepoURL).Tag }}
                  # Commit the changes
                  - uses: git-commit
                    as: commit-changes
                    config:
                      path: ./repo
                      message: "chore: update backstage image to ''${{ imageFrom(vars.imageRepoURL).Tag }}"
                  # Push to the repository
                  - uses: git-push
                    as: push-changes
                    config:
                      path: ./repo
                  # Sync the ArgoCD application
                  - uses: argocd-update
                    as: sync-argocd-app
                    config:
                      apps:
                        - name: ''${{ vars.argoAppName }}
                          namespace: argocd
                          sources:
                            - repoURL: ''${{ vars.gitRepoURLExternal }}
                              desiredRevision: ''${{ outputs['push-changes'].commit }}
        ''
      ];
    };
  };
}
