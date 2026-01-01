# Kargo Extra Applications
# Pipeline credentials, CA certificates, webhook setup
# Mirrors: cdk8s/charts/pipelines/kargo-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost;
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

  # NOTE: Gitea webhooks can be configured manually via UI if needed
  # ArgoCD webhook URL: http://argocd-server.argocd.svc.cluster.local:80/api/webhook
  # Kargo webhook URL: http://kargo-api.kargo.svc.cluster.local:80/webhooks/gitea
  # idpBuilder already uses 60s polling, so webhooks are optional for faster sync

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
                repoURL: gitea-thinkpad.tail286401.ts.net/giteaadmin/backstage-cnoe
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
      # Hub Inner Loop Stage (local-dev on thinkpad)
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
      # Hub Outer Loop Stage (dev on thinkpad)
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
