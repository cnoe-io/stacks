# Kargo Extra Applications
# Pipeline credentials, CA certificates, webhook setup
# Mirrors: cdk8s/charts/pipelines/kargo-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost;
  inherit (config.gitea) serviceName internalPort defaultOwner;
  giteaNamespace = config.gitea.namespace;
  giteaInternalUrl = "http://${serviceName}.${giteaNamespace}.svc.cluster.local:${toString internalPort}";
  isKind = environmentType == "kind";
  isTalos = environmentType == "talos";
in
{
  # Kargo Pipelines Credentials
  applications.kargo-pipelines-credentials = lib.mkIf isKind {
    namespace = "kargo-pipelines";
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
      # kargo-git-credentials - use gitea ClusterSecretStore (Kubernetes provider)
      # Includes repoURL pattern to match both internal and external gitea URLs
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: kargo-git-credentials
          namespace: kargo-pipelines
          labels:
            app.kubernetes.io/name: kargo-git-credentials
            app.kubernetes.io/part-of: kargo-pipelines
            kargo.akuity.io/cred-type: git
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: gitea
          target:
            name: kargo-git-credentials
            creationPolicy: Owner
            template:
              metadata:
                labels:
                  kargo.akuity.io/cred-type: git
              data:
                username: "{{ .username }}"
                password: "{{ .password }}"
                repoURL: "gitea"
                repoURLIsRegex: "true"
          data:
            - secretKey: username
              remoteRef:
                key: gitea-credential
                property: username
            - secretKey: password
              remoteRef:
                key: gitea-credential
                property: password
      ''
      # kargo-argocd-credentials - use argocd ClusterSecretStore
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: kargo-argocd-credentials
          namespace: kargo-pipelines
          labels:
            app.kubernetes.io/name: kargo-argocd-credentials
            app.kubernetes.io/part-of: kargo-pipelines
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: argocd
          target:
            name: kargo-argocd-credentials
            creationPolicy: Owner
          data:
            - secretKey: token
              remoteRef:
                key: argocd-initial-admin-secret
                property: password
      ''
      # ghcr-credentials - use Azure Key Vault for GitHub PAT
      # Note: kargo.akuity.io/cred-type label must be on the SECRET, not just ExternalSecret
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: ghcr-credentials
          namespace: kargo-pipelines
          labels:
            app.kubernetes.io/name: ghcr-credentials
            app.kubernetes.io/part-of: kargo-pipelines
            kargo.akuity.io/cred-type: image
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: ghcr-credentials
            creationPolicy: Owner
            template:
              type: Opaque
              metadata:
                labels:
                  kargo.akuity.io/cred-type: image
              data:
                username: pittampalliorg
                password: "{{ .pat }}"
                repoURL: "ghcr.io/pittampalliorg"
                repoURLIsRegex: "true"
          data:
            - secretKey: pat
              remoteRef:
                key: GITHUB-PAT
      ''
      # kargo-github-app-credentials - GitHub App authentication for Kargo
      # See: https://docs.kargo.io/user-guide/security/managing-credentials#github-app-authentication
      # Note: Using GITHUB-APP-ID as client ID (numeric App ID is deprecated but works)
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: kargo-github-app-credentials
          namespace: kargo-pipelines
          labels:
            app.kubernetes.io/name: kargo-github-app-credentials
            app.kubernetes.io/part-of: kargo-pipelines
            kargo.akuity.io/cred-type: git
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: kargo-github-app-credentials
            creationPolicy: Owner
            template:
              metadata:
                labels:
                  kargo.akuity.io/cred-type: git
              data:
                githubAppID: "{{ .appId }}"
                githubAppPrivateKey: "{{ .privateKey }}"
                githubAppInstallationID: "{{ .installationId }}"
                repoURL: "https://github.com/PittampalliOrg"
                repoURLIsRegex: "true"
          data:
            - secretKey: appId
              remoteRef:
                key: GITHUB-APP-ID
            - secretKey: privateKey
              remoteRef:
                key: GITHUB-APP-PRIVATE-KEY
            - secretKey: installationId
              remoteRef:
                key: GITHUB-APP-INSTALL-ID
      ''
      # kargo-github-webhook-secret - for GitHub webhook signature verification
      # Note: This secret goes in kargo namespace (where kargo-api runs)
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: kargo-github-webhook-secret
          namespace: kargo
          labels:
            app.kubernetes.io/name: kargo-github-webhook-secret
            app.kubernetes.io/part-of: kargo
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: kargo-github-webhook-secret
            creationPolicy: Owner
          data:
            - secretKey: secret
              remoteRef:
                key: GITHUB-WEBHOOK-SECRET
      ''
    ];
  };

  # Kargo CA Certificates (for Gitea TLS)
  applications.kargo-ca-certificates = lib.mkIf isKind {
    namespace = "kargo-pipelines";
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
    };

    resources = {
      configMaps.kargo-ca-certificates = {
        metadata = {
          namespace = "kargo-pipelines";
          labels = {
            "app.kubernetes.io/component" = "ca-certificates";
            "app.kubernetes.io/part-of" = "kargo";
          };
        };
        data = {
          # Empty by default - populated by init job or external process
          "ca-certificates.crt" = "";
        };
      };
    };
  };

  # =========================================================================
  # Kargo Webhook Sync - Declaratively configures Gitea webhooks
  # Creates webhooks in Gitea repos to notify Kargo of new artifacts
  # =========================================================================
  applications.kargo-webhook-sync = lib.mkIf isKind {
    namespace = "kargo";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "80";
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
      # Sync Gitea credentials to kargo namespace using gitea ClusterSecretStore
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: kargo-gitea-credentials
          namespace: kargo
          labels:
            app.kubernetes.io/name: kargo-gitea-credentials
            app.kubernetes.io/part-of: kargo
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: gitea
          target:
            name: kargo-gitea-credentials
            creationPolicy: Owner
          data:
            - secretKey: token
              remoteRef:
                key: gitea-credential
                property: token
      ''
      # ConfigMap with webhook sync script
      ''
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: kargo-webhook-sync-script
          namespace: kargo
        data:
          sync-webhooks.sh: |
            #!/bin/sh

            # Configuration from environment
            # Use HTTP for internal cluster communication
            GITEA_URL="${giteaInternalUrl}"
            KARGO_WEBHOOK_URL="http://kargo-external-webhooks-server.kargo.svc.cluster.local:80"

            # Get webhook path from ClusterConfig (cluster-scoped, best practice)
            # ClusterConfig triggers ALL Warehouses across ALL projects
            # Path format: /webhooks/gitea/<hash>
            WEBHOOK_PATH="/webhooks/gitea/7090e2e781280fe5dce3c1e9e110ad453602198aa7802cf5f834ee925c085738"

            # Repos to configure (manifest repos watched by Kargo Warehouses)
            REPOS="giteaadmin/idpbuilder-${config.cluster.name}-backstage-local-dev-manifests"

            for REPO in $REPOS; do
              REPO_OWNER=$(echo $REPO | cut -d'/' -f1)
              REPO_NAME=$(echo $REPO | cut -d'/' -f2)

              echo "Checking webhooks for $REPO..."
              EXISTING_HOOKS=$(curl -s --connect-timeout 10 --max-time 30 "$GITEA_URL/api/v1/repos/$REPO_OWNER/$REPO_NAME/hooks" \
                -H "Authorization: token $GITEA_TOKEN" 2>&1 || echo "[]")

              # Check if our webhook already exists
              if echo "$EXISTING_HOOKS" | grep -q "$WEBHOOK_PATH"; then
                echo "  Webhook already exists"
              else
                echo "  Creating Kargo webhook..."
                RESULT=$(curl -s --connect-timeout 10 --max-time 30 -X POST "$GITEA_URL/api/v1/repos/$REPO_OWNER/$REPO_NAME/hooks" \
                  -H "Authorization: token $GITEA_TOKEN" \
                  -H "Content-Type: application/json" \
                  -d "{\"type\":\"gitea\",\"config\":{\"url\":\"$KARGO_WEBHOOK_URL$WEBHOOK_PATH\",\"content_type\":\"json\",\"secret\":\"$KARGO_WEBHOOK_SECRET\"},\"events\":[\"push\"],\"active\":true}" 2>&1)
                if echo "$RESULT" | grep -q '"id"'; then
                  echo "  Webhook created successfully"
                else
                  echo "  Failed to create webhook: $RESULT"
                fi
              fi
            done
            echo "Webhook sync complete"
      ''
      # CronJob to ensure webhooks stay configured
      ''
        apiVersion: batch/v1
        kind: CronJob
        metadata:
          name: kargo-webhook-sync
          namespace: kargo
          labels:
            app.kubernetes.io/name: kargo-webhook-sync
            app.kubernetes.io/part-of: kargo
        spec:
          schedule: "0 * * * *"
          successfulJobsHistoryLimit: 1
          failedJobsHistoryLimit: 3
          jobTemplate:
            spec:
              template:
                spec:
                  restartPolicy: OnFailure
                  containers:
                    - name: webhook-sync
                      image: curlimages/curl:8.5.0
                      command: ["/bin/sh", "/scripts/sync-webhooks.sh"]
                      env:
                        - name: GITEA_TOKEN
                          valueFrom:
                            secretKeyRef:
                              name: kargo-gitea-credentials
                              key: token
                        - name: KARGO_WEBHOOK_SECRET
                          value: kargo-gitea-webhook-${config.cluster.name}-secret-2024
                      volumeMounts:
                        - name: scripts
                          mountPath: /scripts
                  volumes:
                    - name: scripts
                      configMap:
                        name: kargo-webhook-sync-script
                        defaultMode: 0755
      ''
      # Job to run webhook sync immediately on deployment
      ''
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: kargo-webhook-sync-init
          namespace: kargo
          annotations:
            argocd.argoproj.io/hook: PostSync
            argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
        spec:
          ttlSecondsAfterFinished: 3600
          template:
            spec:
              restartPolicy: OnFailure
              containers:
                - name: webhook-sync
                  image: curlimages/curl:8.5.0
                  command: ["/bin/sh", "/scripts/sync-webhooks.sh"]
                  env:
                    - name: GITEA_TOKEN
                      valueFrom:
                        secretKeyRef:
                          name: kargo-gitea-credentials
                          key: token
                    - name: KARGO_WEBHOOK_SECRET
                      value: kargo-gitea-webhook-${config.cluster.name}-secret-2024
                  volumeMounts:
                    - name: scripts
                      mountPath: /scripts
              volumes:
                - name: scripts
                  configMap:
                    name: kargo-webhook-sync-script
                    defaultMode: 0755
      ''
    ];
  };

  # NOTE: kargo-backstage-pipeline is defined in kargo-pipelines.nix

  # Hub Kargo Backstage Pipeline (for Talos/Hub)
  applications.hub-kargo-backstage-pipeline = lib.mkIf (isTalos) {
    namespace = "kargo-pipelines";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "82";
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
      # Hub Inner Loop Warehouse (Gitea via Tailscale)
      ''
        apiVersion: kargo.akuity.io/v1alpha1
        kind: Warehouse
        metadata:
          name: hub-backstage-gitea
          namespace: kargo-pipelines
        spec:
          subscriptions:
            - image:
                repoURL: gitea-${config.tailscale.serviceHost}.${config.tailscale.tailnet}/giteaadmin/backstage
      ''
      # Hub Outer Loop Warehouse (GHCR)
      ''
        apiVersion: kargo.akuity.io/v1alpha1
        kind: Warehouse
        metadata:
          name: hub-backstage-ghcr
          namespace: kargo-pipelines
        spec:
          subscriptions:
            - image:
                repoURL: ghcr.io/pittampalliorg/backstage
      ''
      # Hub Inner Loop Stage (local-dev on spoke cluster)
      ''
        apiVersion: kargo.akuity.io/v1alpha1
        kind: Stage
        metadata:
          name: hub-backstage-local-dev
          namespace: kargo-pipelines
        spec:
          requestedFreight:
            - origin:
                kind: Warehouse
                name: hub-backstage-gitea
              sources:
                direct: true
          promotionTemplate:
            spec:
              steps:
                - uses: argocd-update
                  config:
                    apps:
                      - name: hub-backstage-local-dev
                        sources:
                          - repoURL: https://github.com/PittampalliOrg/stacks.git
      ''
      # Hub Outer Loop Stage (dev on spoke cluster)
      ''
        apiVersion: kargo.akuity.io/v1alpha1
        kind: Stage
        metadata:
          name: hub-backstage-dev
          namespace: kargo-pipelines
        spec:
          requestedFreight:
            - origin:
                kind: Warehouse
                name: hub-backstage-ghcr
              sources:
                direct: true
          promotionTemplate:
            spec:
              steps:
                - uses: argocd-update
                  config:
                    apps:
                      - name: hub-backstage-dev
                        sources:
                          - repoURL: https://github.com/PittampalliOrg/stacks.git
      ''
      # Hub Outer Loop Stage (staging on ryzen)
      ''
        apiVersion: kargo.akuity.io/v1alpha1
        kind: Stage
        metadata:
          name: hub-backstage-staging
          namespace: kargo-pipelines
        spec:
          requestedFreight:
            - origin:
                kind: Warehouse
                name: hub-backstage-ghcr
              sources:
                stages:
                  - hub-backstage-dev
          promotionTemplate:
            spec:
              steps:
                - uses: argocd-update
                  config:
                    apps:
                      - name: hub-backstage-staging
                        sources:
                          - repoURL: https://github.com/PittampalliOrg/stacks.git
      ''
    ];
  };
}
