import { Construct } from 'constructs';
import * as k8s from '../imports/k8s';

function toDnsLabel(value: string): string {
  const normalized = value
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+/, '')
    .replace(/-+$/, '');

  if (normalized.length <= 63) return normalized;
  return normalized.slice(0, 63).replace(/-+$/, '');
}

export interface ExternalSecretsWebhookGateOptions {
  /**
   * Prefix for the Job name. Defaults to scope.node.id.
   */
  namePrefix?: string;

  /**
   * ArgoCD sync-wave for the hook Job.
   * @default '-100'
   */
  syncWave?: string;

  /**
   * Max seconds to wait before failing.
   * @default 300
   */
  maxWaitSeconds?: number;
}

/**
 * Adds an ArgoCD PreSync hook Job that waits for the External Secrets webhook
 * service to be reachable before applying any ExternalSecret resources.
 *
 * This prevents race conditions during fresh cluster creation/recreation where
 * ArgoCD may attempt to apply ExternalSecret CRs before the validating webhook
 * is ready, leading to transient sync failures.
 */
export function addExternalSecretsWebhookGate(
  scope: Construct,
  namespace: string,
  options: ExternalSecretsWebhookGateOptions = {},
): void {
  const namePrefix = options.namePrefix ?? scope.node.id;
  const jobName = toDnsLabel(`${namePrefix}-wait-external-secrets-webhook`);
  const syncWave = options.syncWave ?? '-100';
  const maxWaitSeconds = options.maxWaitSeconds ?? 300;
  const maxAttempts = Math.ceil(maxWaitSeconds / 5);

  new k8s.KubeJob(scope, 'external-secrets-webhook-gate', {
    metadata: {
      name: jobName,
      namespace,
      annotations: {
        'argocd.argoproj.io/hook': 'PreSync',
        'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
        'argocd.argoproj.io/sync-wave': syncWave,
      },
      labels: {
        'app.kubernetes.io/name': jobName,
        'app.kubernetes.io/component': 'presync-hook',
        'app.kubernetes.io/part-of': 'external-secrets',
      },
    },
    spec: {
      backoffLimit: 0,
      activeDeadlineSeconds: maxWaitSeconds,
      ttlSecondsAfterFinished: 60,
      template: {
        spec: {
          restartPolicy: 'Never',
          containers: [
            {
              name: 'wait',
              image: 'curlimages/curl:8.5.0',
              command: ['/bin/sh', '-ec'],
              args: [
                [
                  `for i in $(seq 1 ${maxAttempts}); do`,
                  '  if curl -ksS --connect-timeout 2 https://external-secrets-webhook.external-secrets.svc:443/ >/dev/null 2>&1; then',
                  '    echo "external-secrets-webhook reachable"',
                  '    exit 0',
                  '  fi',
                  '  echo "waiting for external-secrets-webhook..."',
                  '  sleep 5',
                  'done',
                  '',
                  'echo "timeout waiting for external-secrets-webhook"',
                  'exit 1',
                ].join('\n'),
              ],
            },
          ],
        },
      },
    },
  });
}

