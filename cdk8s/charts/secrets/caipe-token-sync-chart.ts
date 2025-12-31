/**
 * CaipeTokenSyncChart - Declarative ArgoCD Token Sync for CAIPE
 *
 * This chart creates a fully declarative solution for syncing ArgoCD tokens
 * to Azure Key Vault using External Secrets Operator's PushSecret feature.
 *
 * Architecture:
 * 1. PostSync Job - Generates ArgoCD API token and stores in K8s secret
 * 2. PushSecret - Syncs the K8s secret to Azure Key Vault
 * 3. ExternalSecret (in caipe-secrets-chart) - Pulls token to CAIPE namespace
 *
 * This eliminates the need for imperative scripts during bootstrap.
 *
 * Prerequisites:
 * - ArgoCD installed with 'developer' account having apiKey capability
 * - ClusterSecretStore configured for Azure Key Vault
 * - ServiceAccount with RBAC to create secrets in argocd namespace
 */

import { Chart, ChartProps, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  PushSecret,
  PushSecretSpecDeletionPolicy,
  PushSecretSpecUpdatePolicy,
  PushSecretSpecSecretStoreRefsKind,
} from '../../imports/external-secrets.io';
import { CAIPE_SECRET_STORE, CAIPE_KEYVAULT_KEYS, getClusterSpecificKeyVaultKey } from '../../lib/caipe-helpers';

export interface CaipeTokenSyncChartProps extends ChartProps {
  /**
   * ArgoCD namespace
   * @default 'argocd'
   */
  argocdNamespace?: string;

  /**
   * ArgoCD account to generate token for
   * @default 'developer'
   */
  argocdAccount?: string;

  /**
   * ClusterSecretStore name for Azure Key Vault
   * @default 'azure-keyvault-store'
   */
  clusterSecretStoreName?: string;

  /**
   * Key Vault secret name for the ArgoCD token (base name, will be suffixed with clusterId)
   * @default 'CAIPE-ARGOCD-TOKEN'
   */
  keyVaultSecretName?: string;

  /**
   * Cluster identifier for Key Vault secret naming
   * Used to avoid collisions when multiple clusters push to the same Key Vault
   * @example 'localdev', 'talos', 'kind'
   */
  clusterId?: string;

  /**
   * Sync wave for ArgoCD ordering (should run after ArgoCD is ready)
   * @default '50'
   */
  syncWave?: string;

  /**
   * Enable the token sync (set false to disable)
   * @default true
   */
  enabled?: boolean;
}

export class CaipeTokenSyncChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeTokenSyncChartProps = {}) {
    super(scope, id, props);

    const enabled = props.enabled ?? true;
    if (!enabled) {
      return;
    }

    const argocdNamespace = props.argocdNamespace || 'argocd';
    const argocdAccount = props.argocdAccount || 'developer';
    const clusterSecretStoreName = props.clusterSecretStoreName || CAIPE_SECRET_STORE;
    const clusterId = props.clusterId || '';
    const baseKeyVaultSecretName = props.keyVaultSecretName || CAIPE_KEYVAULT_KEYS.argocdToken;
    // Apply cluster-specific suffix to avoid Key Vault naming collisions
    const keyVaultSecretName = getClusterSpecificKeyVaultKey(baseKeyVaultSecretName, clusterId);
    const syncWave = props.syncWave || '50';

    const labels = {
      'app.kubernetes.io/name': 'caipe-token-sync',
      'app.kubernetes.io/component': 'token-generator',
      'app.kubernetes.io/part-of': 'ai-platform-engineering',
      'app.kubernetes.io/managed-by': 'cdk8s',
    };

    const secretName = 'caipe-argocd-token';
    const serviceAccountName = 'caipe-token-generator';

    // =========================================================================
    // ServiceAccount for the token generator Job
    // =========================================================================

    new k8s.KubeServiceAccount(this, 'sa', {
      metadata: {
        name: serviceAccountName,
        namespace: argocdNamespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
    });

    // =========================================================================
    // Role - permissions to create/update secrets
    // =========================================================================

    new k8s.KubeRole(this, 'role', {
      metadata: {
        name: 'caipe-token-generator',
        namespace: argocdNamespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['create', 'update', 'patch', 'get'],
        },
      ],
    });

    // =========================================================================
    // RoleBinding
    // =========================================================================

    new k8s.KubeRoleBinding(this, 'rolebinding', {
      metadata: {
        name: 'caipe-token-generator',
        namespace: argocdNamespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccountName,
          namespace: argocdNamespace,
        },
      ],
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'caipe-token-generator',
      },
    });

    // =========================================================================
    // Job - Generate ArgoCD token and store in K8s secret
    // This is a PostSync hook that runs after ArgoCD is fully synced
    // =========================================================================

    const job = new k8s.KubeJob(this, 'token-generator-job', {
      metadata: {
        name: 'caipe-token-generator',
        namespace: argocdNamespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
          // Sync hook - runs during sync (not every sync due to HookSucceeded)
          'argocd.argoproj.io/hook': 'Sync',
          // Delete job after successful completion - won't run again until app is recreated
          'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded',
        },
      },
      spec: {
        ttlSecondsAfterFinished: 300, // Cleanup after 5 minutes
        backoffLimit: 3,
        template: {
          metadata: {
            labels: labels,
          },
          spec: {
            serviceAccountName: serviceAccountName,
            restartPolicy: 'OnFailure',
            containers: [
              {
                name: 'token-generator',
                // Use bitnami kubectl image with argocd CLI installed
                image: 'bitnami/kubectl:latest',
                command: ['/bin/bash', '-c'],
                env: [
                  // Set HOME to /tmp so argocd CLI can write config
                  { name: 'HOME', value: '/tmp' },
                ],
                args: [
                  `
set -e

# Install argocd CLI
echo "Installing ArgoCD CLI..."
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v2.11.0/argocd-linux-amd64
chmod +x /tmp/argocd

echo "Checking if ArgoCD token secret already exists..."

# Check if the secret already exists and has a valid token
EXISTING_TOKEN=$(kubectl get secret ${secretName} -n ${argocdNamespace} -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")

if [ -n "$EXISTING_TOKEN" ]; then
  echo "Token secret already exists. Validating token..."

  # Test if the existing token is valid by making an API call
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \\
    -H "Authorization: Bearer $EXISTING_TOKEN" \\
    "https://argocd-server.${argocdNamespace}/api/v1/account" \\
    --insecure 2>/dev/null || echo "000")

  if [ "$RESPONSE" = "200" ]; then
    echo "Existing token is valid. Skipping regeneration."
    exit 0
  fi

  echo "Existing token is invalid (HTTP $RESPONSE). Regenerating..."
fi

echo "Generating new ArgoCD API token for account '${argocdAccount}'..."

# Get admin password from secret
ADMIN_PASSWORD=$(cat /var/run/secrets/argocd/password)

# Login to ArgoCD
/tmp/argocd login argocd-server.${argocdNamespace} \\
  --username admin \\
  --password "$ADMIN_PASSWORD" \\
  --insecure \\
  --grpc-web

# Generate token for the target account
TOKEN=$(/tmp/argocd account generate-token --account ${argocdAccount})

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to generate token"
  exit 1
fi

echo "Token generated successfully"

# Create or update the Kubernetes secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${secretName}
  namespace: ${argocdNamespace}
  labels:
    app.kubernetes.io/name: caipe-token-sync
    app.kubernetes.io/component: argocd-token
    app.kubernetes.io/part-of: ai-platform-engineering
type: Opaque
stringData:
  token: "$TOKEN"
EOF

echo "Secret '${secretName}' created/updated successfully"
`,
                ],
                volumeMounts: [
                  {
                    name: 'argocd-admin-password',
                    mountPath: '/var/run/secrets/argocd',
                    readOnly: true,
                  },
                ],
              },
            ],
            volumes: [
              {
                name: 'argocd-admin-password',
                secret: {
                  secretName: 'argocd-initial-admin-secret',
                  items: [
                    {
                      key: 'password',
                      path: 'password',
                    },
                  ],
                },
              },
            ],
          },
        },
      },
    });

    // =========================================================================
    // PushSecret - Sync the K8s secret to Azure Key Vault
    // =========================================================================

    const pushSecret = new PushSecret(this, 'push-secret', {
      metadata: {
        name: 'caipe-argocd-token-push',
        namespace: argocdNamespace,
        labels: labels,
      },
      spec: {
        // Refresh every hour to ensure token stays in sync
        refreshInterval: '1h',
        // Replace existing secret in Key Vault
        updatePolicy: PushSecretSpecUpdatePolicy.REPLACE,
        // Keep the Key Vault secret when PushSecret is deleted (None = don't delete)
        deletionPolicy: PushSecretSpecDeletionPolicy.NONE,
        secretStoreRefs: [
          {
            name: clusterSecretStoreName,
            kind: PushSecretSpecSecretStoreRefsKind.CLUSTER_SECRET_STORE,
          },
        ],
        selector: {
          secret: {
            name: secretName,
          },
        },
        data: [
          {
            match: {
              secretKey: 'token',
              remoteRef: {
                remoteKey: keyVaultSecretName,
              },
            },
          },
        ],
      },
    });

    // Add sync wave annotation via JsonPatch
    pushSecret.addJsonPatch(
      JsonPatch.add('/metadata/annotations', {
        'argocd.argoproj.io/sync-wave': String(parseInt(syncWave) + 1),
      })
    );
  }
}
