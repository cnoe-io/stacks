import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../imports/k8s';
import { defaultKubectlImage } from '../config/images';

/**
 * Creates a Kubernetes Job that registers vclusters with ArgoCD
 * This is a GitOps-compatible approach that runs declaratively on each sync
 */
export class VclusterRegistrationJobChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    // Create ServiceAccount for the registration job
    const serviceAccount = new k8s.KubeServiceAccount(this, 'vcluster-registration-sa', {
      metadata: {
        name: 'vcluster-registration',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
        },
      },
    });

    // Create ClusterRole for reading vcluster secrets
    const clusterRole = new k8s.KubeClusterRole(this, 'vcluster-registration-reader', {
      metadata: {
        name: 'vcluster-registration-reader',
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
    const role = new k8s.KubeRole(this, 'vcluster-registration-writer', {
      metadata: {
        name: 'vcluster-registration-writer',
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
    new k8s.KubeClusterRoleBinding(this, 'vcluster-registration-reader-binding', {
      metadata: {
        name: 'vcluster-registration-reader-binding',
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
    new k8s.KubeRoleBinding(this, 'vcluster-registration-writer-binding', {
      metadata: {
        name: 'vcluster-registration-writer-binding',
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

echo "Starting vCluster registration process..."

# Define vClusters to register
declare -A VCLUSTERS=(
  ["dev"]="dev-vcluster"
  ["staging"]="staging-vcluster"
)

for env in "\${!VCLUSTERS[@]}"; do
  namespace="\${VCLUSTERS[\$env]}"
  cluster_name="\$env-vcluster"
  secret_name="vc-vcluster-\$env-helm"
  
  echo "Processing \$cluster_name in namespace \$namespace..."
  
  # Check if vcluster secret exists
  if ! kubectl get secret -n "\$namespace" "\$secret_name" &> /dev/null; then
    echo "Secret \$secret_name not found in namespace \$namespace, skipping..."
    continue
  fi
  
  echo "Found secret \$secret_name, retrieving credentials..."
  
  # Extract credentials from vcluster secret
  client_key=\$(kubectl get secret -n "\$namespace" "\$secret_name" --template='{{index .data "client-key" }}')
  client_certificate=\$(kubectl get secret -n "\$namespace" "\$secret_name" --template='{{index .data "client-certificate" }}')
  certificate_authority=\$(kubectl get secret -n "\$namespace" "\$secret_name" --template='{{index .data "certificate-authority" }}')
  
  # Create or update ArgoCD cluster secret
  echo "Creating/updating ArgoCD cluster secret for \$cluster_name..."
  
  cat <<EOF | kubectl apply -f -
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
  
  echo "Successfully registered \$cluster_name"
done

echo "vCluster registration process completed successfully"
`;

    const configMap = new k8s.KubeConfigMap(this, 'vcluster-registration-script', {
      metadata: {
        name: 'vcluster-registration-script',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
        },
      },
      data: {
        'register-vclusters.sh': registrationScript,
      },
    });

    // Create the Job that runs the registration
    new k8s.KubeJob(this, 'vcluster-registration-job', {
      metadata: {
        name: 'vcluster-registration',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          // Removed hook annotations - this is now a regular resource
        },
      },
      spec: {
        ttlSecondsAfterFinished: 300, // Clean up after 5 minutes
        template: {
          metadata: {
            name: 'vcluster-registration',
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
    });
  }
}
