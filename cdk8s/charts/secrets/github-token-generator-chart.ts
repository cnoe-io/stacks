/**
 * GithubTokenGeneratorChart - GitHub App-based Token Generation for CAIPE
 *
 * This chart creates a fully declarative solution for generating short-lived
 * GitHub access tokens using ESO's GithubAccessToken generator and GitHub Apps.
 *
 * Architecture:
 * 1. ExternalSecret - Pulls GitHub App private key from Azure Key Vault
 * 2. GithubAccessToken Generator - Creates short-lived tokens using GitHub App
 * 3. ExternalSecret (in caipe-secrets-chart) - Uses generator to create token secret
 *
 * Best Practices (from GitHub and ESO docs):
 * - Uses GitHub App instead of PAT (more secure, better audit trail)
 * - Tokens expire after 60 minutes (short-lived)
 * - Tokens can be scoped to specific repos and permissions
 * - Refresh interval should be < 60 minutes (we use 30m)
 *
 * Prerequisites:
 * - GitHub App registered with appropriate permissions
 * - GitHub App installed on target organization/repos
 * - App private key stored in Azure Key Vault
 * - App ID and Installation ID configured
 *
 * @see https://external-secrets.io/latest/api/generator/github/
 * @see https://docs.github.com/en/apps/creating-github-apps
 */

import { Chart, ChartProps, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecDataFromSourceRefGeneratorRefKind,
} from '../../imports/external-secrets.io';
import {
  GithubAccessToken,
} from '../../imports/generators.external-secrets.io';
import { CAIPE_SECRET_STORE, CAIPE_NAMESPACE } from '../../lib/caipe-helpers';

export interface GithubTokenGeneratorChartProps extends ChartProps {
  /**
   * Namespace for the generator resources
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * GitHub App ID
   * @see https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app
   */
  appId: string;

  /**
   * GitHub App Installation ID
   * @see https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app
   */
  installId: string;

  /**
   * Key Vault secret name containing the GitHub App private key (PEM format)
   * @default 'GITHUB-APP-PRIVATE-KEY'
   */
  privateKeyVaultSecret?: string;

  /**
   * GitHub API URL (for GitHub Enterprise)
   * @default '' (uses https://api.github.com)
   */
  githubApiUrl?: string;

  /**
   * Optional list of repository names to scope the token
   * If empty, token has access to all repos the app is installed on
   */
  repositories?: string[];

  /**
   * Optional permissions for the token
   * @example { contents: 'read', issues: 'write' }
   * @see https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app
   */
  permissions?: Record<string, string>;

  /**
   * ClusterSecretStore name for Azure Key Vault
   * @default 'azure-keyvault-store'
   */
  clusterSecretStoreName?: string;

  /**
   * Token refresh interval (must be < 60 minutes due to GitHub token expiration)
   * @default '30m'
   */
  refreshInterval?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '-70'
   */
  syncWave?: string;
}

export class GithubTokenGeneratorChart extends Chart {
  constructor(scope: Construct, id: string, props: GithubTokenGeneratorChartProps) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const clusterSecretStoreName = props.clusterSecretStoreName || CAIPE_SECRET_STORE;
    const privateKeyVaultSecret = props.privateKeyVaultSecret || 'GITHUB-APP-PRIVATE-KEY';
    const refreshInterval = props.refreshInterval || '30m';
    const syncWave = props.syncWave || '-70';

    const labels = {
      'app.kubernetes.io/name': 'github-token-generator',
      'app.kubernetes.io/component': 'token-generator',
      'app.kubernetes.io/part-of': 'ai-platform-engineering',
      'app.kubernetes.io/managed-by': 'cdk8s',
    };

    const privateKeySecretName = 'github-app-private-key';

    // =========================================================================
    // ExternalSecret - Pull GitHub App private key from Azure Key Vault
    // =========================================================================

    const privateKeySecret = new ExternalSecret(this, 'private-key-secret', {
      metadata: {
        name: privateKeySecretName,
        namespace: namespace,
        labels: labels,
      },
      spec: {
        refreshInterval: '1h', // Private key doesn't change often
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: privateKeySecretName,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: labels,
            },
          },
        },
        data: [
          {
            secretKey: 'privateKey',
            remoteRef: { key: privateKeyVaultSecret },
          },
        ],
      },
    });
    privateKeySecret.addJsonPatch(
      JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave })
    );

    // =========================================================================
    // GithubAccessToken Generator
    // Creates short-lived GitHub access tokens using GitHub App authentication
    // =========================================================================

    const generator = new GithubAccessToken(this, 'generator', {
      metadata: {
        name: 'github-app-token',
        namespace: namespace,
        labels: labels,
      },
      spec: {
        appId: props.appId,
        installId: props.installId,
        url: props.githubApiUrl || '',
        repositories: props.repositories,
        permissions: props.permissions,
        auth: {
          privateKey: {
            secretRef: {
              name: privateKeySecretName,
              key: 'privateKey',
              namespace: namespace,
            },
          },
        },
      },
    });
    generator.addJsonPatch(
      JsonPatch.add('/metadata/annotations', {
        'argocd.argoproj.io/sync-wave': String(parseInt(syncWave) + 1),
      })
    );

    // =========================================================================
    // ExternalSecret - Generate GitHub token using the generator
    // This creates the actual short-lived token that agents use
    // =========================================================================

    const tokenSecret = new ExternalSecret(this, 'token-secret', {
      metadata: {
        name: 'agent-github-secret',
        namespace: namespace,
        labels: { ...labels, 'app.kubernetes.io/component': 'agent-github' },
      },
      spec: {
        // Must be < 60 minutes (GitHub token expiration)
        refreshInterval: refreshInterval,
        target: {
          name: 'agent-github-secret',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: { ...labels, 'app.kubernetes.io/component': 'agent-github' },
            },
            // Map the generator output to expected env var name
            data: {
              'GITHUB_PERSONAL_ACCESS_TOKEN': '{{ .token }}',
              'GITHUB_TOKEN': '{{ .token }}',
            },
          },
        },
        dataFrom: [
          {
            sourceRef: {
              generatorRef: {
                apiVersion: 'generators.external-secrets.io/v1alpha1',
                kind: ExternalSecretSpecDataFromSourceRefGeneratorRefKind.GITHUB_ACCESS_TOKEN,
                name: 'github-app-token',
              },
            },
          },
        ],
      },
    });
    tokenSecret.addJsonPatch(
      JsonPatch.add('/metadata/annotations', {
        'argocd.argoproj.io/sync-wave': String(parseInt(syncWave) + 2),
      })
    );
  }
}
