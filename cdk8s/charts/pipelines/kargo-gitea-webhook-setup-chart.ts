import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { 
  ExternalSecret,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetDeletionPolicy,
  ExternalSecretSpecDataRemoteRefConversionStrategy
} from '../../imports/external-secrets.io';
import { createEnvExternalSecret } from '../../lib/eso-helpers';
import { JsonPatch } from 'cdk8s';

export class KargoGiteaWebhookSetupChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const namespace = 'kargo-pipelines';

    // Create ExternalSecret for Gitea API credentials for webhook setup
    // This pulls the current token from the Gitea namespace, ensuring it's always fresh
    const giteaCreds = createEnvExternalSecret(this, 'gitea-api-credentials-external', {
      externalName: 'gitea-credentials-external',
      name: 'gitea-credentials',
      namespace,
      refreshInterval: '5m',
      secretStoreRef: { name: 'gitea', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      deletionPolicy: ExternalSecretSpecTargetDeletionPolicy.RETAIN,
      mappings: [
        { key: 'token', remoteRef: { key: 'gitea-credential', property: 'token' } },
        { key: 'username', remoteRef: { key: 'gitea-credential', property: 'username' } },
        { key: 'password', remoteRef: { key: 'gitea-credential', property: 'password' } },
      ],
    });
    giteaCreds.addJsonPatch(JsonPatch.add('/metadata/labels', {
      'app.kubernetes.io/name': 'gitea-credentials',
      'app.kubernetes.io/part-of': 'kargo-pipelines',
      'app.kubernetes.io/component': 'webhook-setup'
    }));
    giteaCreds.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-20' }));

    // Create a ConfigMap with the webhook configuration script
    new k8s.KubeConfigMap(this, 'gitea-webhook-setup-script', {
      metadata: {
        name: 'gitea-webhook-setup-script',
        namespace: 'kargo-pipelines',
      },
      data: {
        'setup-webhooks.sh': `#!/bin/bash
set -e

echo "Starting Gitea webhook configuration..."

# Configuration
GITEA_URL="https://gitea.cnoe.localtest.me:8443"
WEBHOOK_URL="https://kargo-webhooks.cnoe.localtest.me:8443/webhooks/github/661cf0989545b1bd92b763966c09315f5e6fa5d0b48e79ee79fa983acde57967"
WEBHOOK_SECRET="lwxtOFx10Jrox11Zi40r3L3zEvR6J8q9"

# Get API token from mounted secret
API_TOKEN=$(cat /gitea-credentials/token)

echo "Checking for existing webhooks..."

# Check if webhook already exists
EXISTING_HOOKS=$(curl -k -s -X GET \\
  "$GITEA_URL/api/v1/admin/hooks" \\
  -H "Authorization: token $API_TOKEN")

# Check if our webhook URL already exists
if echo "$EXISTING_HOOKS" | grep -q "$WEBHOOK_URL"; then
  echo "Webhook already exists, skipping creation"
  exit 0
fi

echo "Creating system-wide webhook for package events..."

# Create system-wide webhook for package events
RESPONSE=$(curl -k -s -w "\\nHTTP_STATUS:%{http_code}" -X POST \\
  "$GITEA_URL/api/v1/admin/hooks" \\
  -H "Authorization: token $API_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{
    "type": "gitea",
    "config": {
      "url": "'"$WEBHOOK_URL"'",
      "content_type": "json",
      "secret": "'"$WEBHOOK_SECRET"'",
      "insecure_ssl": "true"
    },
    "events": ["push", "create", "delete", "release", "package"],
    "active": true
  }')

# Extract HTTP status code
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS:/p' | sed '$d')

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
  echo "Successfully created webhook!"
  echo "Response: $BODY"
else
  echo "Failed to create webhook. Status: $HTTP_STATUS"
  echo "Response: $BODY"
  exit 1
fi

echo "Webhook configuration completed successfully!"
`
      }
    });

    // Create a Job to run the webhook setup
    new k8s.KubeJob(this, 'gitea-webhook-setup-job', {
      metadata: {
        name: 'gitea-webhook-setup',
        namespace: 'kargo-pipelines',
        annotations: {
          'argocd.argoproj.io/hook': 'PostSync',
          'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded'
        }
      },
      spec: {
        backoffLimit: 3,
        ttlSecondsAfterFinished: 3600,
        template: {
          spec: {
            restartPolicy: 'OnFailure',
            containers: [
              {
                name: 'webhook-setup',
                image: 'curlimages/curl:8.5.0',
                command: ['/bin/sh'],
                args: ['/scripts/setup-webhooks.sh'],
                volumeMounts: [
                  { name: 'script', mountPath: '/scripts', readOnly: true },
                  { name: 'gitea-credentials', mountPath: '/gitea-credentials', readOnly: true }
                ]
              }
            ],
            volumes: [
              { name: 'script', configMap: { name: 'gitea-webhook-setup-script', defaultMode: 0o755 as any } },
              { name: 'gitea-credentials', secret: { secretName: 'gitea-credentials', items: [{ key: 'token', path: 'token' }] } }
            ]
          }
        }
      }
    });

    // Create a CronJob for periodic webhook verification (optional)
    new k8s.KubeCronJob(this, 'gitea-webhook-verify-cronjob', {
      metadata: { name: 'gitea-webhook-verify', namespace: 'kargo-pipelines' },
      spec: {
        schedule: '0 */6 * * *',
        successfulJobsHistoryLimit: 1,
        failedJobsHistoryLimit: 2,
        jobTemplate: {
          spec: {
            backoffLimit: 1,
            ttlSecondsAfterFinished: 3600,
            template: {
              spec: {
                restartPolicy: 'OnFailure',
                containers: [
                  {
                    name: 'webhook-verify',
                    image: 'curlimages/curl:8.5.0',
                    command: ['/bin/sh'],
                    args: ['/scripts/setup-webhooks.sh'],
                    volumeMounts: [
                      { name: 'script', mountPath: '/scripts', readOnly: true },
                      { name: 'gitea-credentials', mountPath: '/gitea-credentials', readOnly: true }
                    ]
                  }
                ],
                volumes: [
                  { name: 'script', configMap: { name: 'gitea-webhook-setup-script', defaultMode: 0o755 as any } },
                  { name: 'gitea-credentials', secret: { secretName: 'gitea-credentials', items: [{ key: 'token', path: 'token' }] } }
                ]
              }
            }
          }
        }
      }
    });
  }
}
