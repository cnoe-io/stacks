/**
 * WorkloadIdentityPatchChart - Patches ServiceAccount for Azure Workload Identity
 * Feature: 102-bootstrap-talos-argocd
 *
 * This chart patches an existing ServiceAccount with the annotations
 * required for Azure Workload Identity federation:
 * - azure.workload.identity/client-id
 * - azure.workload.identity/tenant-id
 *
 * The Azure Workload Identity webhook will then inject:
 * - Environment variables for Azure SDK
 * - Projected volume with federated token
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeServiceAccount } from '../../imports/k8s';

export interface WorkloadIdentityPatchChartProps extends ChartProps {
  /**
   * Azure AD application (client) ID
   */
  clientId: string;

  /**
   * Azure AD tenant ID
   */
  tenantId: string;

  /**
   * ServiceAccount name to create/patch
   * @default 'external-secrets'
   */
  serviceAccountName?: string;

  /**
   * ServiceAccount namespace
   * @default 'external-secrets'
   */
  serviceAccountNamespace?: string;
}

export class WorkloadIdentityPatchChart extends Chart {
  constructor(scope: Construct, id: string, props: WorkloadIdentityPatchChartProps) {
    super(scope, id, props);

    const {
      clientId,
      tenantId,
      serviceAccountName = 'external-secrets',
      serviceAccountNamespace = 'external-secrets',
    } = props;

    // Validate required props
    if (!clientId || !tenantId) {
      console.warn('WorkloadIdentityPatchChart: clientId and tenantId are required for Azure Workload Identity');
    }

    // Create ServiceAccount with Workload Identity annotations
    // This will be merged with the existing SA created by ESO Helm chart
    // using ArgoCD's ServerSideApply sync option
    new KubeServiceAccount(this, 'sa-patch', {
      metadata: {
        name: serviceAccountName,
        namespace: serviceAccountNamespace,
        annotations: {
          'azure.workload.identity/client-id': clientId || '',
          'azure.workload.identity/tenant-id': tenantId || '',
        },
        labels: {
          'azure.workload.identity/use': 'true',
        },
      },
    });
  }
}
