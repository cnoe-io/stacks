/**
 * Contract: External Secrets Operator CDK8s Chart Properties
 * Feature: 102-bootstrap-talos-argocd
 *
 * Defines the TypeScript interfaces for ESO-related CDK8s charts.
 */

import { ChartProps } from 'cdk8s';

/**
 * Properties for the External Secrets Operator Helm Chart
 */
export interface EsoHelmChartProps extends ChartProps {
  /**
   * Helm chart version to install
   * @default '0.9.13'
   */
  version?: string;

  /**
   * Install CRDs with Helm
   * @default true
   */
  installCrds?: boolean;

  /**
   * Enable webhook for validation
   * @default true
   */
  enableWebhook?: boolean;

  /**
   * Number of operator replicas
   * @default 2
   */
  replicaCount?: number;

  /**
   * Additional Helm values to merge
   */
  additionalValues?: Record<string, unknown>;
}

/**
 * Properties for the Workload Identity ServiceAccount patch
 */
export interface WorkloadIdentityChartProps extends ChartProps {
  /**
   * Azure AD application (client) ID
   */
  clientId: string;

  /**
   * Azure AD tenant ID
   */
  tenantId: string;

  /**
   * ServiceAccount name to patch
   * @default 'external-secrets'
   */
  serviceAccountName?: string;

  /**
   * ServiceAccount namespace
   * @default 'external-secrets'
   */
  serviceAccountNamespace?: string;

  /**
   * Sync wave for ordering (must be after ESO install)
   * @default '-94'
   */
  syncWave?: string;
}

/**
 * Properties for the ClusterSecretStore
 */
export interface ClusterSecretStoreChartProps extends ChartProps {
  /**
   * Store name (cluster-scoped)
   * @default 'azure-keyvault-store'
   */
  storeName?: string;

  /**
   * Azure Key Vault name (without .vault.azure.net suffix)
   */
  keyVaultName: string;

  /**
   * ServiceAccount reference for authentication
   */
  serviceAccountRef: {
    name: string;
    namespace: string;
  };

  /**
   * Sync wave for ordering (must be after workload identity patch)
   * @default '-92'
   */
  syncWave?: string;
}

/**
 * Properties for individual ExternalSecret resources
 */
export interface ExternalSecretChartProps extends ChartProps {
  /**
   * ExternalSecret name
   */
  secretName: string;

  /**
   * Target namespace for the Kubernetes Secret
   */
  targetNamespace: string;

  /**
   * ClusterSecretStore name to reference
   * @default 'azure-keyvault-store'
   */
  secretStoreName?: string;

  /**
   * Refresh interval for secret sync
   * @default '1h'
   */
  refreshInterval?: string;

  /**
   * Secret data mappings
   */
  data: ExternalSecretDataMapping[];

  /**
   * Creation policy for target Secret
   * @default 'Owner'
   */
  creationPolicy?: 'Owner' | 'Merge' | 'None';

  /**
   * Sync wave for ordering
   */
  syncWave?: string;
}

/**
 * Mapping from Key Vault secret to Kubernetes Secret key
 */
export interface ExternalSecretDataMapping {
  /**
   * Key name in the Kubernetes Secret
   */
  secretKey: string;

  /**
   * Reference to the remote secret
   */
  remoteRef: {
    /**
     * Key Vault secret name
     */
    key: string;

    /**
     * Optional JSON property path (if secret value is JSON)
     */
    property?: string;
  };
}

/**
 * Common Azure Key Vault secret names used in bootstrap
 */
export const AZURE_KEYVAULT_SECRETS = {
  /** Tailscale OAuth client ID */
  TAILSCALE_OAUTH_CLIENT_ID: 'TAILSCALE-OAUTH-CLIENT-ID',

  /** Tailscale OAuth client secret */
  TAILSCALE_OAUTH_CLIENT_SECRET: 'TAILSCALE-OAUTH-CLIENT-SECRET',

  /** Tailscale auth key (tagged, reusable, ephemeral) */
  TAILSCALE_AUTH_KEY: 'TAILSCALE-AUTH-KEY',

  /** GitHub App private key (for ArgoCD) */
  GITHUB_APP_PRIVATE_KEY: 'github-app-private-key',

  /** GitHub App ID */
  GITHUB_APP_ID: 'github-app-id',

  /** GitHub App installation ID */
  GITHUB_APP_INSTALLATION_ID: 'github-app-installation-id',
} as const;
