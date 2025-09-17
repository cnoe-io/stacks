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
    const registrationScript = `#!/bin/sh
set -eu

log() {
  printf '[%s] %s
' "\$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

ENVIRONMENTS="dev staging"

success_count=0
skip_count=0
error_count=0

for env in $ENVIRONMENTS; do
  namespace="\${env}-vcluster"
  cluster_name="\${env}-vcluster"
  secret_name="vc-vcluster-\${env}-helm"

  log "Processing \${cluster_name} in namespace \${namespace}..."

  if ! kubectl get secret -n "$namespace" "$secret_name" >/dev/null 2>&1; then
    log "Secret \${secret_name} not found in namespace \${namespace}, skipping..."
    skip_count=$((skip_count + 1))
    continue
  fi

  if kubectl get secret -n argocd "cluster-\${cluster_name}" >/dev/null 2>&1; then
    log "Cluster secret for \${cluster_name} already exists, checking if update needed..."
    current_server=$(kubectl get secret -n argocd "cluster-\${cluster_name}" -o jsonpath='{.data.server}' 2>/dev/null | base64 -d 2>/dev/null || printf '')
    expected_server="https://vcluster-\${env}-helm.\${namespace}.svc:443"

    if [ "$current_server" = "$expected_server" ]; then
      log "Cluster \${cluster_name} registration is up to date"
      success_count=$((success_count + 1))
      continue
    fi
    log "Updating registration for \${cluster_name} (server endpoint changed)"
  fi

  log "Retrieving credentials for \${cluster_name}..."

  client_key=$(kubectl get secret -n "$namespace" "$secret_name" --template='{{index .data "client-key" }}' 2>/dev/null || printf '')
  client_certificate=$(kubectl get secret -n "$namespace" "$secret_name" --template='{{index .data "client-certificate" }}' 2>/dev/null || printf '')
  certificate_authority=$(kubectl get secret -n "$namespace" "$secret_name" --template='{{index .data "certificate-authority" }}' 2>/dev/null || printf '')

  if [ -z "$client_key" ] || [ -z "$client_certificate" ] || [ -z "$certificate_authority" ]; then
    log "ERROR: Failed to extract credentials for \${cluster_name}"
    error_count=$((error_count + 1))
    continue
  fi

  if kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-\${cluster_name}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    cnoe.io.vcluster-class: app-runtime
    cnoe.io.vcluster-name: \${env}
    environment: \${env}
    azure.workload.identity/enabled: "true"
    managed-by: vcluster-registration-cronjob
type: Opaque
stringData:
  name: \${cluster_name}
  server: https://vcluster-\${env}-helm.\${namespace}.svc:443
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "\${certificate_authority}",
        "certData": "\${client_certificate}",
        "keyData": "\${client_key}"
      }
    }
EOF
  then
    log "Successfully registered \${cluster_name}"
    success_count=$((success_count + 1))
  else
    log "ERROR: Failed to register \${cluster_name}"
    error_count=$((error_count + 1))
  fi
done

log "vCluster registration process completed"
log "Summary: Success: \${success_count}, Skipped: \${skip_count}, Errors: \${error_count}"

if [ "$error_count" -gt 0 ]; then
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
                    command: ['/bin/sh', '/scripts/register-vclusters.sh'],
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
