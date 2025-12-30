/**
 * BackstageTokenSyncChart - Declarative Backstage Token Sync for CAIPE
 *
 * This chart creates a fully declarative solution for generating Backstage
 * service-to-service tokens and syncing them to Azure Key Vault using
 * External Secrets Operator's PushSecret feature.
 *
 * Architecture:
 * 1. Sync Job - Generates random static token and stores in K8s secret
 * 2. PushSecret - Syncs the K8s secret to Azure Key Vault
 * 3. ExternalSecret (in caipe-secrets-chart) - Pulls token to CAIPE namespace
 *
 * The token is configured in Backstage via backend.auth.externalAccess
 * static token configuration (see BackstageChart app-config overlay).
 *
 * Best Practices (from Backstage docs):
 * - Static tokens should be sufficiently long (we use 32 bytes base64)
 * - Tokens should be rotated regularly (handled by PushSecret refresh)
 * - Access restrictions should limit token scope (configured in Backstage)
 *
 * Prerequisites:
 * - ClusterSecretStore configured for Azure Key Vault
 * - Backstage configured with externalAccess to accept the token
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

export interface BackstageTokenSyncChartProps extends ChartProps {
  /**
   * Backstage namespace
   * @default 'backstage'
   */
  backstageNamespace?: string;

  /**
   * ClusterSecretStore name for Azure Key Vault
   * @default 'azure-keyvault-store'
   */
  clusterSecretStoreName?: string;

  /**
   * Key Vault secret name for the Backstage token (base name, will be suffixed with clusterId)
   * @default 'CAIPE-BACKSTAGE-API-TOKEN'
   */
  keyVaultSecretName?: string;

  /**
   * Cluster identifier for Key Vault secret naming
   * Used to avoid collisions when multiple clusters push to the same Key Vault
   * @example 'localdev', 'talos', 'kind'
   */
  clusterId?: string;

  /**
   * Sync wave for ArgoCD ordering (should run early, before Backstage)
   * @default '-20'
   */
  syncWave?: string;

  /**
   * Enable the token sync (set false to disable)
   * @default true
   */
  enabled?: boolean;
}

export class BackstageTokenSyncChart extends Chart {
  constructor(scope: Construct, id: string, props: BackstageTokenSyncChartProps = {}) {
    super(scope, id, props);

    const enabled = props.enabled ?? true;
    if (!enabled) {
      return;
    }

    const backstageNamespace = props.backstageNamespace || 'backstage';
    const clusterSecretStoreName = props.clusterSecretStoreName || CAIPE_SECRET_STORE;
    const clusterId = props.clusterId || '';
    const baseKeyVaultSecretName = props.keyVaultSecretName || CAIPE_KEYVAULT_KEYS.backstageApiToken;
    // Apply cluster-specific suffix to avoid Key Vault naming collisions
    const keyVaultSecretName = getClusterSpecificKeyVaultKey(baseKeyVaultSecretName, clusterId);
    const syncWave = props.syncWave || '-20';

    const labels = {
      'app.kubernetes.io/name': 'backstage-token-sync',
      'app.kubernetes.io/component': 'token-generator',
      'app.kubernetes.io/part-of': 'backstage',
      'app.kubernetes.io/managed-by': 'cdk8s',
    };

    const secretName = 'backstage-api-token';
    const serviceAccountName = 'backstage-token-generator';

    // =========================================================================
    // ServiceAccount for the token generator Job
    // =========================================================================

    new k8s.KubeServiceAccount(this, 'sa', {
      metadata: {
        name: serviceAccountName,
        namespace: backstageNamespace,
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
        name: 'backstage-token-generator',
        namespace: backstageNamespace,
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
        name: 'backstage-token-generator',
        namespace: backstageNamespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccountName,
          namespace: backstageNamespace,
        },
      ],
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'backstage-token-generator',
      },
    });

    // =========================================================================
    // Job - Generate Backstage API token and store in K8s secret
    // Uses Sync hook with HookSucceeded delete policy (runs once per app creation)
    // =========================================================================

    new k8s.KubeJob(this, 'token-generator-job', {
      metadata: {
        name: 'backstage-token-generator',
        namespace: backstageNamespace,
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
                // Use kubectl image with openssl for token generation
                image: 'bitnami/kubectl:latest',
                command: ['/bin/bash', '-c'],
                args: [
                  `
set -e

echo "Checking if Backstage API token secret already exists..."

# Check if the secret already exists and has a valid token
EXISTING_TOKEN=$(kubectl get secret ${secretName} -n ${backstageNamespace} -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")

if [ -n "$EXISTING_TOKEN" ] && [ "\${#EXISTING_TOKEN}" -gt 20 ]; then
  echo "Token secret already exists with valid token (length: \${#EXISTING_TOKEN}). Skipping regeneration."
  exit 0
fi

echo "Generating new Backstage API token..."

# Generate a cryptographically secure random token (32 bytes = 256 bits)
# Using /dev/urandom which is available in the bitnami/kubectl image
TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '\\n')

if [ -z "$TOKEN" ] || [ "\${#TOKEN}" -lt 20 ]; then
  echo "ERROR: Failed to generate token"
  exit 1
fi

echo "Token generated successfully (length: \${#TOKEN})"

# Create or update the Kubernetes secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${secretName}
  namespace: ${backstageNamespace}
  labels:
    app.kubernetes.io/name: backstage-token-sync
    app.kubernetes.io/component: api-token
    app.kubernetes.io/part-of: backstage
type: Opaque
stringData:
  token: "$TOKEN"
EOF

echo "Secret '${secretName}' created/updated successfully"
`,
                ],
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
        name: 'backstage-api-token-push',
        namespace: backstageNamespace,
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

    // Add sync wave annotation via JsonPatch (should be after the Job)
    pushSecret.addJsonPatch(
      JsonPatch.add('/metadata/annotations', {
        'argocd.argoproj.io/sync-wave': String(parseInt(syncWave) + 1),
      })
    );
  }
}
