import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../imports/k8s';
import { defaultKubectlImage } from '../config/images';

/**
 * Creates a CronJob that periodically registers vclusters with ArgoCD
 * This ensures clusters stay registered even after restarts or failures
 */
export class VclusterRegistrationCronJobChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    // Create ServiceAccount for the registration cronjob
    const serviceAccount = new k8s.KubeServiceAccount(this, 'vcluster-registration-cronjob-sa', {
      metadata: {
        name: 'vcluster-registration-cronjob',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '25',
        },
      },
    });

    // Create ClusterRole for reading vcluster secrets
    const clusterRole = new k8s.KubeClusterRole(this, 'vcluster-registration-cronjob-reader', {
      metadata: {
        name: 'vcluster-registration-cronjob-reader',
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'list'],
        },
        {
          apiGroups: [''],
          resources: ['namespaces'],
          verbs: ['get', 'list'],
        },
      ],
    });

    // Create Role for creating/updating ArgoCD cluster secrets
    const role = new k8s.KubeRole(this, 'vcluster-registration-cronjob-writer', {
      metadata: {
        name: 'vcluster-registration-cronjob-writer',
        namespace: 'argocd',
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['create', 'update', 'patch', 'get', 'list'],
        },
      ],
    });

    // Bind ClusterRole to ServiceAccount
    new k8s.KubeClusterRoleBinding(this, 'vcluster-registration-cronjob-reader-binding', {
      metadata: {
        name: 'vcluster-registration-cronjob-reader-binding',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: clusterRole.name,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccount.name,
          namespace: 'argocd',
        },
      ],
    });

    // Bind Role to ServiceAccount
    new k8s.KubeRoleBinding(this, 'vcluster-registration-cronjob-writer-binding', {
      metadata: {
        name: 'vcluster-registration-cronjob-writer-binding',
        namespace: 'argocd',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: role.name,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccount.name,
          namespace: 'argocd',
        },
      ],
    });

    // Create the registration script as a ConfigMap
    const registrationScript = `#!/bin/bash
set -e

echo "[$(date)] Starting vCluster registration process..."

# Define vClusters to register
declare -A VCLUSTERS=(
  ["dev"]="dev-vcluster"
  ["staging"]="staging-vcluster"
)

success_count=0
skip_count=0
error_count=0

for env in "\${!VCLUSTERS[@]}"; do
  namespace="\${VCLUSTERS[\$env]}"
  cluster_name="\$env-vcluster"
  secret_name="vc-vcluster-\$env-helm"
  
  echo "[$(date)] Processing \$cluster_name in namespace \$namespace..."
  
  # Check if vcluster secret exists
  if ! kubectl get secret -n "\$namespace" "\$secret_name" &> /dev/null; then
    echo "[$(date)] Secret \$secret_name not found in namespace \$namespace, skipping..."
    ((skip_count++))
    continue
  fi
  
  # Check if cluster secret already exists and is up to date
  if kubectl get secret -n argocd "cluster-\$cluster_name" &> /dev/null; then
    echo "[$(date)] Cluster secret for \$cluster_name already exists, checking if update needed..."
    
    # Get current server endpoint
    current_server=\$(kubectl get secret -n argocd "cluster-\$cluster_name" -o jsonpath='{.data.server}' | base64 -d 2>/dev/null || echo "")
    expected_server="https://vcluster-\$env-helm.\$namespace.svc:443"
    
    if [ "\$current_server" == "\$expected_server" ]; then
      echo "[$(date)] Cluster \$cluster_name registration is up to date"
      ((success_count++))
      continue
    fi
    echo "[$(date)] Updating registration for \$cluster_name (server endpoint changed)"
  fi
  
  echo "[$(date)] Retrieving credentials for \$cluster_name..."
  
  # Extract credentials from vcluster secret with error handling
  client_key=\$(kubectl get secret -n "\$namespace" "\$secret_name" --template='{{index .data "client-key" }}' 2>/dev/null || echo "")
  client_certificate=\$(kubectl get secret -n "\$namespace" "\$secret_name" --template='{{index .data "client-certificate" }}' 2>/dev/null || echo "")
  certificate_authority=\$(kubectl get secret -n "\$namespace" "\$secret_name" --template='{{index .data "certificate-authority" }}' 2>/dev/null || echo "")
  
  if [ -z "\$client_key" ] || [ -z "\$client_certificate" ] || [ -z "\$certificate_authority" ]; then
    echo "[$(date)] ERROR: Failed to extract credentials for \$cluster_name"
    ((error_count++))
    continue
  fi
  
  # Create or update ArgoCD cluster secret
  echo "[$(date)] Creating/updating ArgoCD cluster secret for \$cluster_name..."
  
  if cat <<EOF | kubectl apply -f - 2>/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: cluster-\$cluster_name
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    cnoe.io.vcluster-class: app-runtime
    cnoe.io.vcluster-name: \$env
    environment: \$env
    azure.workload.identity/enabled: "true"
    managed-by: vcluster-registration-cronjob
type: Opaque
stringData:
  name: \$cluster_name
  server: https://vcluster-\$env-helm.\$namespace.svc:443
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "\$certificate_authority",
        "certData": "\$client_certificate",
        "keyData": "\$client_key"
      }
    }
EOF
  then
    echo "[$(date)] Successfully registered \$cluster_name"
    ((success_count++))
  else
    echo "[$(date)] ERROR: Failed to register \$cluster_name"
    ((error_count++))
  fi
done

echo "[$(date)] vCluster registration process completed"
echo "[$(date)] Summary: Success: \$success_count, Skipped: \$skip_count, Errors: \$error_count"

# Exit with error if any registrations failed
if [ \$error_count -gt 0 ]; then
  exit 1
fi
`;

    const configMap = new k8s.KubeConfigMap(this, 'vcluster-registration-cronjob-script', {
      metadata: {
        name: 'vcluster-registration-cronjob-script',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '25',
        },
      },
      data: {
        'register-vclusters.sh': registrationScript,
      },
    });

    // Create the CronJob that runs the registration periodically
    new k8s.KubeCronJob(this, 'vcluster-registration-cronjob', {
      metadata: {
        name: 'vcluster-registration-cronjob',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '25',
        },
      },
      spec: {
        schedule: '*/5 * * * *', // Run every 5 minutes
        concurrencyPolicy: 'Forbid', // Don't run concurrent jobs
        successfulJobsHistoryLimit: 1,
        failedJobsHistoryLimit: 3,
        jobTemplate: {
          spec: {
            ttlSecondsAfterFinished: 300, // Clean up after 5 minutes
            backoffLimit: 2, // Retry twice on failure
            template: {
              metadata: {
                labels: {
                  'app.kubernetes.io/name': 'vcluster-registration-cronjob',
                  'app.kubernetes.io/component': 'registration',
                },
              },
              spec: {
                serviceAccountName: serviceAccount.name,
                restartPolicy: 'OnFailure',
                containers: [
                  {
                    name: 'register',
                    image: defaultKubectlImage,
                    command: ['/bin/bash'],
                    args: ['/scripts/register-vclusters.sh'],
                    volumeMounts: [
                      {
                        name: 'script',
                        mountPath: '/scripts',
                      },
                    ],
                    resources: {
                      requests: {
                        cpu: k8s.Quantity.fromString('50m'),
                        memory: k8s.Quantity.fromString('64Mi'),
                      },
                      limits: {
                        cpu: k8s.Quantity.fromString('100m'),
                        memory: k8s.Quantity.fromString('128Mi'),
                      },
                    },
                  },
                ],
                volumes: [
                  {
                    name: 'script',
                    configMap: {
                      name: configMap.name,
                      defaultMode: 0o755,
                    },
                  },
                ],
              },
            },
          },
        },
      },
    });
  }
}
