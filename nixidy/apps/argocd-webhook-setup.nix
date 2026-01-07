# ArgoCD Webhook Setup - Configures Gitea to send webhooks to ArgoCD
# This enables instant sync on push instead of waiting for ArgoCD's 3-minute polling interval
# Based on: nixidy/apps/kargo-extras.nix webhook setup pattern
{ config, lib, ... }:
let
  isKind = config.environmentType == "kind";
  namespace = "argocd";

  # ArgoCD internal webhook endpoint
  argoCDWebhookUrl = "http://argocd-server.argocd.svc.cluster.local/api/webhook";

  # Gitea URLs
  giteaUrl = "https://gitea.cnoe.localtest.me:8443";
in
{
  config = lib.mkIf isKind {
    applications.argocd-webhook-setup = {
      inherit namespace;

      annotations = {
        # Run after ArgoCD and Gitea are ready
        "argocd.argoproj.io/sync-wave" = "100";
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
        # ExternalSecret to get Gitea API credentials
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: gitea-argocd-webhook-creds
            namespace: ${namespace}
            annotations:
              argocd.argoproj.io/sync-wave: "-10"
            labels:
              app.kubernetes.io/name: argocd-webhook-setup
              app.kubernetes.io/component: credentials
          spec:
            refreshInterval: "5m"
            secretStoreRef:
              name: gitea
              kind: ClusterSecretStore
            target:
              name: gitea-argocd-webhook-creds
              creationPolicy: Owner
            data:
              - secretKey: token
                remoteRef:
                  key: gitea-credential
                  property: token
        ''

        # ConfigMap with the webhook setup script
        # Uses repo-level webhooks instead of system-level (system webhooks don't persist in this Gitea)
        # Optimized: parallel API calls for faster execution
        ''
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: argocd-webhook-setup-script
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: argocd-webhook-setup
              app.kubernetes.io/component: webhook-automation
          data:
            setup-webhooks.sh: |
              #!/bin/sh
              set -e

              echo "Starting Gitea webhook configuration for ArgoCD..."
              echo "Target: ${argoCDWebhookUrl}"

              # Configuration
              GITEA_URL="${giteaUrl}"
              WEBHOOK_URL="${argoCDWebhookUrl}"
              PARALLEL_JOBS=10

              # Get API token from mounted secret
              API_TOKEN=$(cat /gitea-credentials/token)
              export API_TOKEN GITEA_URL WEBHOOK_URL

              echo "Fetching repository list..."

              # Get all repos (up to 200) - use jq to parse JSON properly
              REPOS=$(curl -k -s -H "Authorization: token $API_TOKEN" \
                "$GITEA_URL/api/v1/repos/search?limit=200" | \
                jq -r '.data[].full_name')

              TOTAL=$(echo "$REPOS" | wc -l)
              echo "Found $TOTAL repositories, processing with $PARALLEL_JOBS parallel jobs..."

              # Create helper script for parallel execution
              cat > /tmp/process-repo.sh << 'SCRIPT'
              #!/bin/sh
              REPO="$1"
              # Check if ArgoCD webhook already exists
              EXISTS=$(curl -k -s -H "Authorization: token $API_TOKEN" \
                "$GITEA_URL/api/v1/repos/$REPO/hooks" | \
                jq '[.[] | select(.config.url | contains("argocd"))] | length' 2>/dev/null || echo "0")

              if [ "$EXISTS" -gt 0 ]; then
                echo "skip:$REPO"
                exit 0
              fi

              # Create webhook
              RESULT=$(curl -k -s -w "%{http_code}" -o /dev/null -X POST \
                "$GITEA_URL/api/v1/repos/$REPO/hooks" \
                -H "Authorization: token $API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"type\":\"gitea\",\"config\":{\"url\":\"$WEBHOOK_URL\",\"content_type\":\"json\"},\"events\":[\"push\"],\"active\":true}")

              if [ "$RESULT" = "201" ]; then
                echo "created:$REPO"
              else
                echo "failed:$REPO:$RESULT"
              fi
              SCRIPT
              chmod +x /tmp/process-repo.sh

              # Process repos in parallel
              RESULTS=$(echo "$REPOS" | xargs -P $PARALLEL_JOBS -I {} /tmp/process-repo.sh {})

              # Count results
              CREATED=$(echo "$RESULTS" | grep -c "^created:" || echo "0")
              SKIPPED=$(echo "$RESULTS" | grep -c "^skip:" || echo "0")
              FAILED=$(echo "$RESULTS" | grep -c "^failed:" || echo "0")

              # Show created repos
              echo "$RESULTS" | grep "^created:" | sed 's/^created:/[+] /'

              echo ""
              echo "ArgoCD webhook configuration completed!"
              echo "Created: $CREATED, Skipped: $SKIPPED, Failed: $FAILED"
              echo "Gitea will now send push notifications to ArgoCD instantly."
        ''

        # Job to run webhook setup (PostSync hook)
        # Optimized: pre-built image (no apk install), resource limits
        ''
          apiVersion: batch/v1
          kind: Job
          metadata:
            name: argocd-webhook-setup
            namespace: ${namespace}
            annotations:
              argocd.argoproj.io/hook: PostSync
              argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
            labels:
              app.kubernetes.io/name: argocd-webhook-setup
          spec:
            backoffLimit: 3
            ttlSecondsAfterFinished: 3600
            template:
              spec:
                restartPolicy: OnFailure
                containers:
                  - name: webhook-setup
                    image: dwdraju/alpine-curl-jq:latest
                    command: ["/bin/sh", "/scripts/setup-webhooks.sh"]
                    resources:
                      requests:
                        cpu: 50m
                        memory: 64Mi
                      limits:
                        cpu: 200m
                        memory: 128Mi
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
                      name: argocd-webhook-setup-script
                      defaultMode: 0755
                  - name: gitea-credentials
                    secret:
                      secretName: gitea-argocd-webhook-creds
                      items:
                        - key: token
                          path: token
        ''

        # CronJob for periodic webhook verification (every 6 hours)
        # Optimized: pre-built image, resource limits
        ''
          apiVersion: batch/v1
          kind: CronJob
          metadata:
            name: argocd-webhook-verify
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: argocd-webhook-verify
          spec:
            schedule: "0 */6 * * *"
            successfulJobsHistoryLimit: 1
            failedJobsHistoryLimit: 2
            jobTemplate:
              spec:
                backoffLimit: 1
                ttlSecondsAfterFinished: 3600
                template:
                  spec:
                    restartPolicy: OnFailure
                    containers:
                      - name: webhook-verify
                        image: dwdraju/alpine-curl-jq:latest
                        command: ["/bin/sh", "/scripts/setup-webhooks.sh"]
                        resources:
                          requests:
                            cpu: 50m
                            memory: 64Mi
                          limits:
                            cpu: 200m
                            memory: 128Mi
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
                          name: argocd-webhook-setup-script
                          defaultMode: 0755
                      - name: gitea-credentials
                        secret:
                          secretName: gitea-argocd-webhook-creds
                          items:
                            - key: token
                              path: token
        ''
      ];
    };
  };
}
