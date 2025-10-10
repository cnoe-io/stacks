/**
 * KagentCrdsChart - Deploys kagent CRDs via Helm chart
 *
 * This chart installs the Custom Resource Definitions required by kagent:
 * - Agent
 * - ModelConfig
 * - MCPServer
 * - Memory
 * - RemoteMCPServer
 * - ToolServer
 *
 * Must be deployed before KagentChart and KmcpChart
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeNamespace } from '../../imports/k8s';

export class KagentCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const ns = 'kagent';

    // Create namespace with very early sync wave
    new KubeNamespace(this, 'namespace', {
      metadata: {
        name: ns,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-120',
        },
        labels: {
          'app.kubernetes.io/name': 'kagent',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // Deploy kagent CRDs using official Helm chart
    new Helm(this, 'kagent-crds', {
      chart: 'oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds',
      namespace: ns,
      releaseName: 'kagent-crds',
      // No values needed for CRDs chart
      values: {},
    });
  }
}
