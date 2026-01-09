# idpBuilder Gitea configuration - KIND only
# This app is only deployed in KIND (local development) where idpBuilder manages Gitea
# Mirrors: cdk8s/charts/infra/idpbuilder-gitea-chart.ts
#
# Key responsibilities:
# 1. Create the gitea namespace with proper labels
# 2. Store webhook configuration for ArgoCD
# 3. Create the default organization (giteaAdmin) for Backstage templates
{ config, lib, ... }:
let
  # Only include for kind environment
  isKind = config.environmentType == "kind";
  inherit (config.gitea) namespace serviceName internalPort defaultOwner adminUsername;
  giteaInternalUrl = "http://${serviceName}.${namespace}.svc.cluster.local:${toString internalPort}";
in
{
  # Conditionally include this application based on environment type
  config = lib.mkIf isKind {
    applications.idpbuilder-gitea = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-80";
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
        # Namespace for Gitea
        namespaces.${namespace} = {
          metadata.labels = {
            "app.kubernetes.io/managed-by" = "nixidy";
            "app.kubernetes.io/component" = "git-server";
            "app.kubernetes.io/part-of" = "developer-platform";
          };
        };

        # ConfigMap with Gitea webhook configuration for ArgoCD
        configMaps.gitea-webhook-config = {
          metadata.namespace = namespace;
          data = {
            "description" = "Gitea webhook configuration for ArgoCD notifications";
            "argocd-webhook-url" = "http://argocd-server.argocd.svc.cluster.local/api/webhook";
            "gitea-internal-url" = giteaInternalUrl;
            "gitea-default-owner" = defaultOwner;
          };
        };
      };

      # YAML resources for organization creation
      yamls = [
        # ConfigMap with organization creation script
        ''
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: gitea-org-setup-script
            namespace: ${namespace}
          data:
            setup-org.sh: |
              #!/bin/sh
              set -e

              GITEA_URL="${giteaInternalUrl}"
              ORG_NAME="${defaultOwner}"

              # Read credentials from mounted secret
              GITEA_USER=$(cat /gitea-credentials/username)
              GITEA_PASS=$(cat /gitea-credentials/password)

              echo "Waiting for Gitea to be ready..."
              until curl -sf "$GITEA_URL/api/v1/version" > /dev/null 2>&1; do
                echo "Gitea not ready, waiting..."
                sleep 5
              done
              echo "Gitea is ready!"

              # Check if organization already exists
              echo "Checking if organization '$ORG_NAME' exists..."
              ORG_CHECK=$(curl -sf -o /dev/null -w "%{http_code}" \
                -u "$GITEA_USER:$GITEA_PASS" \
                "$GITEA_URL/api/v1/orgs/$ORG_NAME" 2>/dev/null || echo "000")

              if [ "$ORG_CHECK" = "200" ]; then
                echo "Organization '$ORG_NAME' already exists, skipping creation"
                exit 0
              fi

              echo "Creating organization '$ORG_NAME'..."
              RESULT=$(curl -sf -X POST \
                -u "$GITEA_USER:$GITEA_PASS" \
                -H "Content-Type: application/json" \
                -d "{\"username\": \"$ORG_NAME\", \"visibility\": \"public\", \"description\": \"Default organization for Backstage templates\"}" \
                "$GITEA_URL/api/v1/orgs" 2>&1) || {
                  echo "Failed to create organization: $RESULT"
                  # Check if it was created by someone else
                  ORG_RECHECK=$(curl -sf -o /dev/null -w "%{http_code}" \
                    -u "$GITEA_USER:$GITEA_PASS" \
                    "$GITEA_URL/api/v1/orgs/$ORG_NAME" 2>/dev/null || echo "000")
                  if [ "$ORG_RECHECK" = "200" ]; then
                    echo "Organization exists now (created by another process)"
                    exit 0
                  fi
                  exit 1
                }

              echo "Organization '$ORG_NAME' created successfully!"
        ''

        # Job to create the organization
        ''
          apiVersion: batch/v1
          kind: Job
          metadata:
            name: gitea-org-setup
            namespace: ${namespace}
            annotations:
              argocd.argoproj.io/hook: PostSync
              argocd.argoproj.io/hook-delete-policy: HookSucceeded
          spec:
            ttlSecondsAfterFinished: 300
            backoffLimit: 5
            template:
              spec:
                restartPolicy: OnFailure
                serviceAccountName: default
                containers:
                  - name: setup
                    image: alpine/curl:latest
                    command: ["/bin/sh", "/scripts/setup-org.sh"]
                    volumeMounts:
                      - name: script
                        mountPath: /scripts
                        readOnly: true
                      - name: gitea-credentials
                        mountPath: /gitea-credentials
                        readOnly: true
                volumes:
                  - name: script
                    configMap:
                      name: gitea-org-setup-script
                      defaultMode: 0755
                  - name: gitea-credentials
                    secret:
                      secretName: gitea-credential
                      items:
                        - key: username
                          path: username
                        - key: password
                          path: password
        ''
      ];
    };
  };
}
