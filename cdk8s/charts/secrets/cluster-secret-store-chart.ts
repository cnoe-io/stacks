/**
 * ClusterSecretStoreChart - Creates ClusterSecretStore for Azure Key Vault
 * Feature: 102-bootstrap-talos-argocd
 *
 * This chart creates a ClusterSecretStore that:
 * - Points to Azure Key Vault
 * - Uses Workload Identity for authentication
 * - Is cluster-scoped (usable from any namespace)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ClusterSecretStore,
  ClusterSecretStoreSpecProviderAzurekvAuthType,
} from '../../imports/external-secrets.io';

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
}

export class ClusterSecretStoreChart extends Chart {
  constructor(scope: Construct, id: string, props: ClusterSecretStoreChartProps) {
    super(scope, id, props);

    const {
      storeName = 'azure-keyvault-store',
      keyVaultName,
      serviceAccountRef,
    } = props;

    // Validate required props
    if (!keyVaultName) {
      throw new Error('ClusterSecretStoreChart: keyVaultName is required. Set AZURE_KEYVAULT_NAME in your .env file.');
    }
    if (!serviceAccountRef?.name || !serviceAccountRef?.namespace) {
      throw new Error('ClusterSecretStoreChart: serviceAccountRef.name and namespace are required');
    }

    // Warn if keyVaultName looks like a full URL (common mistake)
    if (keyVaultName.includes('.vault.azure.net')) {
      console.warn('ClusterSecretStoreChart: keyVaultName should be just the vault name, not the full URL');
    }

    // Build Key Vault URL
    const vaultUrl = `https://${keyVaultName}.vault.azure.net`;

    // Create ClusterSecretStore
    new ClusterSecretStore(this, 'cluster-secret-store', {
      metadata: {
        name: storeName,
        labels: {
          'app.kubernetes.io/managed-by': 'cdk8s',
          'app.kubernetes.io/name': storeName,
          'app.kubernetes.io/component': 'secrets',
        },
      },
      spec: {
        provider: {
          azurekv: {
            vaultUrl: vaultUrl,
            authType: ClusterSecretStoreSpecProviderAzurekvAuthType.WORKLOAD_IDENTITY,
            serviceAccountRef: {
              name: serviceAccountRef.name,
              namespace: serviceAccountRef.namespace,
            },
          },
        },
      },
    });
  }
}
