import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { defaultKubectlImage } from '../../config/images';

export interface ArgoCDTokenGeneratorJobChartProps extends ChartProps {
  namespace?: string;
}

/**
 * Job to generate ArgoCD API token and store it in Azure Key Vault
 */
export class ArgoCDTokenGeneratorJobChart extends Chart {
  constructor(scope: Construct, id: string, props: ArgoCDTokenGeneratorJobChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'ai-platform-engineering';

    // Service Account for the job
    new k8s.KubeServiceAccount(this, 'token-generator-sa', {
      metadata: {
        name: 'argocd-token-generator',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'argocd-token-generator',
          'app.kubernetes.io/part-of': 'ai-platform-engineering'
        }
      }
    });

    // Role with permissions to read argocd secrets and update azure keyvault secrets
    new k8s.KubeRole(this, 'token-generator-role', {
      metadata: {
        name: 'argocd-token-generator',
        namespace: 'argocd'
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'list'],
          resourceNames: ['argocd-initial-admin-secret']
        }
      ]
    });

    // RoleBinding in argocd namespace
    new k8s.KubeRoleBinding(this, 'token-generator-rolebinding', {
      metadata: {
        name: 'argocd-token-generator',
        namespace: 'argocd'
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'argocd-token-generator'
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'argocd-token-generator',
          namespace
        }
      ]
    });

    // Job to generate token
    new k8s.KubeJob(this, 'token-generator-job', {
      metadata: {
        name: 'argocd-token-generator',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'argocd-token-generator',
          'app.kubernetes.io/part-of': 'ai-platform-engineering'
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-50',
          'argocd.argoproj.io/hook': 'PostSync',
          'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded'
        }
      },
      spec: {
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': 'argocd-token-generator',
              'app.kubernetes.io/part-of': 'ai-platform-engineering'
            }
          },
          spec: {
            serviceAccountName: 'argocd-token-generator',
            restartPolicy: 'OnFailure',
            containers: [
              {
                name: 'token-generator',
                image: defaultKubectlImage,
                command: ['/bin/bash'],
                args: [
                  '-c',
                  `
set -e
echo "Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)

echo "Logging into ArgoCD..."
kubectl exec -n argocd deployment/argocd-server -- argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

echo "Generating API token..."
TOKEN=$(kubectl exec -n argocd deployment/argocd-server -- argocd account generate-token --account admin)

echo "Token generated successfully"
echo "Please update Azure Key Vault secret 'ai-platform-engineering-argocd' with:"
echo "{"
echo "  \"ARGOCD_TOKEN\": \"$TOKEN\","
echo "  \"ARGOCD_API_URL\": \"https://argocd-server.argocd.svc.cluster.local\","
echo "  \"ARGOCD_VERIFY_SSL\": \"false\""
echo "}"
                  `
                ]
              }
            ]
          }
        }
      }
    });
  }
}
