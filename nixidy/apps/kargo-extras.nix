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
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: kargo-git-credentials
          namespace: kargo-pipelines
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: kargo-git-credentials
            creationPolicy: Owner
          data:
            - secretKey: username
              remoteRef:
                key: GITEA-ADMIN-USERNAME
            - secretKey: password
              remoteRef:
                key: GITEA-ADMIN-PASSWORD
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: kargo-argocd-credentials
          namespace: kargo-pipelines
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: kargo-argocd-credentials
            creationPolicy: Owner
          data:
            - secretKey: token
              remoteRef:
                key: KARGO-ARGOCD-TOKEN
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: ghcr-credentials
          namespace: kargo-pipelines
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: ghcr-credentials
            creationPolicy: Owner
            template:
              type: kubernetes.io/dockerconfigjson
              data:
                .dockerconfigjson: '{{ .dockerconfigjson }}'
          data:
            - secretKey: dockerconfigjson
              remoteRef:
                key: GHCR-DOCKERCFG
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

  # Kargo Gitea Webhook Setup
  applications.kargo-gitea-webhook-setup = lib.mkIf isKind {
    namespace = "kargo-pipelines";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "85";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      serviceAccounts.webhook-setup = {
        metadata.namespace = "kargo-pipelines";
      };

      configMaps.webhook-setup-script = {
        metadata.namespace = "kargo-pipelines";
        data = {
          "setup.sh" = ''
            #!/bin/sh
            set -e
            echo "Setting up Kargo webhook in Gitea..."

            GITEA_URL="http://my-gitea-http.gitea.svc.cluster.local:3000"
            KARGO_WEBHOOK_URL="http://kargo-api.kargo.svc.cluster.local/webhooks/gitea"

            # Check if webhook exists
            EXISTING=$(curl -s -u "$GITEA_USER:$GITEA_PASSWORD" \
              "$GITEA_URL/api/v1/repos/giteaadmin/stacks/hooks" | jq '.[] | select(.config.url | contains("kargo"))')

            if [ -z "$EXISTING" ]; then
              echo "Creating webhook..."
              curl -X POST -u "$GITEA_USER:$GITEA_PASSWORD" \
                -H "Content-Type: application/json" \
                -d "{\"type\":\"gitea\",\"config\":{\"url\":\"$KARGO_WEBHOOK_URL\",\"content_type\":\"json\"},\"events\":[\"push\"],\"active\":true}" \
                "$GITEA_URL/api/v1/repos/giteaadmin/stacks/hooks"
              echo "Webhook created"
            else
              echo "Webhook already exists"
            fi
          '';
        };
      };

      jobs.webhook-setup = {
        metadata = {
          namespace = "kargo-pipelines";
          labels.app = "webhook-setup";
        };
        spec = {
          backoffLimit = 5;
          template = {
            spec = {
              serviceAccountName = "webhook-setup";
              restartPolicy = "OnFailure";
              containers = [{
                name = "setup";
                image = "curlimages/curl:8.5.0";
                command = ["/bin/sh" "/scripts/setup.sh"];
                env = [
                  { name = "GITEA_USER"; valueFrom.secretKeyRef = { name = "kargo-git-credentials"; key = "username"; }; }
                  { name = "GITEA_PASSWORD"; valueFrom.secretKeyRef = { name = "kargo-git-credentials"; key = "password"; }; }
                ];
                volumeMounts = [{
                  name = "scripts";
                  mountPath = "/scripts";
                }];
              }];
              volumes = [{
                name = "scripts";
                configMap.name = "webhook-setup-script";
              }];
            };
          };
        };
      };
    };
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
                repoURL: ghcr.io/pittampalliorg/backstage-cnoe
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
