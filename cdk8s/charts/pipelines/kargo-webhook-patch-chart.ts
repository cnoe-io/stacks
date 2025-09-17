import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeJob, KubeServiceAccount, KubeClusterRole, KubeClusterRoleBinding, Quantity } from '../../imports/k8s';
import { defaultKubectlImage } from '../../config/images';

export interface KargoWebhookPatchChartProps extends ChartProps {
  namespace?: string;
}

export class KargoWebhookPatchChart extends Chart {
  constructor(scope: Construct, id: string, props: KargoWebhookPatchChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'kargo';

    // Create service account for the patch job
    new KubeServiceAccount(this, 'patch-webhook-sa', {
      metadata: {
        name: 'kargo-patch-webhook',
        namespace: namespace,
      },
    });

    // Create role for the patch job
    new KubeClusterRole(this, 'patch-webhook-role', {
      metadata: {
        name: 'kargo-patch-webhook',
      },
      rules: [
        {
          apiGroups: ['admissionregistration.k8s.io'],
          resources: ['validatingwebhookconfigurations', 'mutatingwebhookconfigurations'],
          verbs: ['get', 'list', 'patch', 'update'],
        },
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get'],
        },
      ],
    });

    // Bind the role to the service account
    new KubeClusterRoleBinding(this, 'patch-webhook-binding', {
      metadata: {
        name: 'kargo-patch-webhook',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'kargo-patch-webhook',
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: 'kargo-patch-webhook',
        namespace: namespace,
      }],
    });

    // Create a job to patch webhook configurations with CA bundle
    new KubeJob(this, 'patch-webhook-ca', {
      metadata: {
        name: 'kargo-patch-webhook-ca',
        namespace: namespace,
      },
      spec: {
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': 'kargo-patch-webhook',
              'app.kubernetes.io/component': 'job',
            },
          },
          spec: {
            serviceAccountName: 'kargo-patch-webhook',
            restartPolicy: 'OnFailure',
            containers: [{
              name: 'patch',
              image: defaultKubectlImage,
              command: ['/bin/sh'],
              resources: {
                requests: {
                  cpu: Quantity.fromString('50m'),
                  memory: Quantity.fromString('64Mi'),
                },
                limits: {
                  cpu: Quantity.fromString('100m'),
                  memory: Quantity.fromString('128Mi'),
                },
              },
              args: [
                '-c',
                `
                set -eu
                
                if ! command -v jq >/dev/null 2>&1; then
                  echo "Installing jq (required for webhook patching)..."
                  apk add --no-cache jq >/dev/null 2>&1
                fi
                
                echo "Patching webhook configurations with CA bundle..."
                
                echo "Waiting for kargo-webhooks-server-cert secret..."
                i=1
                while [ "$i" -le 60 ]; do
                  if kubectl get secret kargo-webhooks-server-cert -n \${namespace} >/dev/null 2>&1; then
                    echo "Secret found!"
                    break
                  fi
                  echo "Waiting for secret... attempt $i/60"
                  i=$((i + 1))
                  sleep 5
                done
                
                if [ "$i" -gt 60 ]; then
                  echo "ERROR: Timed out waiting for kargo-webhooks-server-cert secret"
                  exit 1
                fi
                
                CA_CERT=$(kubectl get secret kargo-webhooks-server-cert -n \${namespace} -o jsonpath='{.data.tls\.crt}')
                
                if [ -z "$CA_CERT" ]; then
                  echo "ERROR: Failed to extract CA certificate from secret"
                  exit 1
                fi
                
                echo "Waiting for webhook configurations..."
                i=1
                while [ "$i" -le 60 ]; do
                  if kubectl get validatingwebhookconfiguration kargo >/dev/null 2>&1 && \
                     kubectl get mutatingwebhookconfiguration kargo >/dev/null 2>&1; then
                    echo "Webhook configurations found!"
                    break
                  fi
                  echo "Waiting for webhook configurations... attempt $i/60"
                  i=$((i + 1))
                  sleep 5
                done
                
                if [ "$i" -gt 60 ]; then
                  echo "ERROR: Timed out waiting for webhook configurations"
                  exit 1
                fi
                
                echo "Patching validating webhook configuration..."
                WEBHOOK_COUNT=$(kubectl get validatingwebhookconfiguration kargo -o json | jq '.webhooks | length')
                echo "Found $WEBHOOK_COUNT validating webhooks"
                
                PATCHES=""
                idx=0
                while [ "$idx" -lt "$WEBHOOK_COUNT" ]; do
                  if [ -n "$PATCHES" ]; then
                    PATCHES="$PATCHES,"
                  fi
                  PATCHES="$PATCHES{\"op\": \"add\", \"path\": \"/webhooks/$idx/clientConfig/caBundle\", \"value\": \"$CA_CERT\"}"
                  idx=$((idx + 1))
                done
                
                kubectl patch validatingwebhookconfiguration kargo --type='json' -p="[$PATCHES]"
                
                echo "Patching mutating webhook configuration..."
                WEBHOOK_COUNT=$(kubectl get mutatingwebhookconfiguration kargo -o json | jq '.webhooks | length')
                echo "Found $WEBHOOK_COUNT mutating webhooks"
                
                PATCHES=""
                idx=0
                while [ "$idx" -lt "$WEBHOOK_COUNT" ]; do
                  if [ -n "$PATCHES" ]; then
                    PATCHES="$PATCHES,"
                  fi
                  PATCHES="$PATCHES{\"op\": \"add\", \"path\": \"/webhooks/$idx/clientConfig/caBundle\", \"value\": \"$CA_CERT\"}"
                  idx=$((idx + 1))
                done
                
                kubectl patch mutatingwebhookconfiguration kargo --type='json' -p="[$PATCHES]"
                
                echo "Webhook configurations patched successfully"
                `
              ],
            }],
          },
        },
        backoffLimit: 3,
        activeDeadlineSeconds: 600, // 10 minutes timeout
      },
    });
  }
}
