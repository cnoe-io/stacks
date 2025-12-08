/**
 * EsoHelmChart - Deploys External Secrets Operator via Helm
 * Feature: 102-bootstrap-talos-argocd
 *
 * This chart deploys ESO using the official Helm chart which:
 * - Installs ESO controller and webhook
 * - Installs CRDs (ClusterSecretStore, ExternalSecret, etc.)
 * - Configures RBAC for secret management
 *
 * Helm Chart: https://external-secrets.io/latest/introduction/getting-started/
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';

export interface EsoHelmChartProps extends ChartProps {
  /**
   * ESO Helm chart version
   * @default '0.9.13'
   */
  version?: string;

  /**
   * Namespace for ESO deployment
   * @default 'external-secrets'
   */
  namespace?: string;

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
   * Enable Azure Workload Identity configuration.
   * When true, configures environment variables and projected token volumes
   * for Azure Workload Identity authentication WITHOUT the webhook.
   * This is required for Talos clusters that don't have the Azure WI webhook.
   * @default false
   */
  enableAzureWorkloadIdentity?: boolean;

  /**
   * Azure AD Client ID (required if enableAzureWorkloadIdentity is true)
   */
  azureClientId?: string;

  /**
   * Azure AD Tenant ID (required if enableAzureWorkloadIdentity is true)
   */
  azureTenantId?: string;

  /**
   * Additional Helm values to merge
   */
  additionalValues?: Record<string, unknown>;
}

export class EsoHelmChart extends Chart {
  constructor(scope: Construct, id: string, props: EsoHelmChartProps = {}) {
    super(scope, id, props);

    const {
      version = '0.9.13',
      namespace = 'external-secrets',
      installCrds = true,
      enableWebhook = true,
      replicaCount = 2,
      enableAzureWorkloadIdentity = false,
      azureClientId = '',
      azureTenantId = '',
      additionalValues = {},
    } = props;

    // Validate Azure WI configuration
    if (enableAzureWorkloadIdentity && (!azureClientId || !azureTenantId)) {
      console.warn('EsoHelmChart: Azure Workload Identity enabled but clientId or tenantId is missing');
    }

    // Base values for ESO
    const baseValues: Record<string, unknown> = {
      // CRD installation
      installCRDs: installCrds,

      // Webhook configuration
      webhook: {
        create: enableWebhook,
        port: 9443,
        resources: {
          requests: {
            cpu: '50m',
            memory: '64Mi',
          },
          limits: {
            cpu: '200m',
            memory: '128Mi',
          },
        },
      },

      // Controller configuration
      replicaCount: replicaCount,
      resources: {
        requests: {
          cpu: '100m',
          memory: '128Mi',
        },
        limits: {
          cpu: '500m',
          memory: '512Mi',
        },
      },

      // Service account
      serviceAccount: {
        create: true,
        name: 'external-secrets',
        automount: true,
      },

      // RBAC
      rbac: {
        create: true,
      },

      // Metrics
      metrics: {
        enabled: true,
        service: {
          enabled: true,
          port: 8080,
        },
      },

      // Pod disruption budget for HA
      podDisruptionBudget: {
        enabled: replicaCount > 1,
        minAvailable: 1,
      },

      // Security context
      podSecurityContext: {
        runAsNonRoot: true,
        seccompProfile: {
          type: 'RuntimeDefault',
        },
      },
    };

    // Add Azure Workload Identity configuration if enabled
    // This is needed for Talos clusters that don't have the Azure WI webhook
    if (enableAzureWorkloadIdentity && azureClientId && azureTenantId) {
      // Environment variables for Azure SDK to use Workload Identity
      baseValues.extraEnv = [
        {
          name: 'AZURE_CLIENT_ID',
          value: azureClientId,
        },
        {
          name: 'AZURE_TENANT_ID',
          value: azureTenantId,
        },
        {
          name: 'AZURE_FEDERATED_TOKEN_FILE',
          value: '/var/run/secrets/azure/tokens/azure-identity-token',
        },
      ];

      // Projected volume for service account token (federated identity)
      baseValues.extraVolumes = [
        {
          name: 'azure-identity-token',
          projected: {
            sources: [
              {
                serviceAccountToken: {
                  audience: 'api://AzureADTokenExchange',
                  expirationSeconds: 3600,
                  path: 'azure-identity-token',
                },
              },
            ],
          },
        },
      ];

      baseValues.extraVolumeMounts = [
        {
          name: 'azure-identity-token',
          mountPath: '/var/run/secrets/azure/tokens',
          readOnly: true,
        },
      ];

      // Add labels to ServiceAccount for documentation (actual annotations are in WorkloadIdentityPatchChart)
      baseValues.serviceAccount = {
        ...((baseValues.serviceAccount as Record<string, unknown>) || {}),
        labels: {
          'azure.workload.identity/use': 'true',
        },
      };
    }

    // Merge with additional values
    const mergedValues = { ...baseValues, ...additionalValues };

    // Deploy ESO using official Helm chart
    new Helm(this, 'external-secrets', {
      chart: 'external-secrets',
      repo: 'https://charts.external-secrets.io',
      version: version,
      namespace: namespace,
      releaseName: 'external-secrets',
      values: mergedValues,
    });
  }
}
