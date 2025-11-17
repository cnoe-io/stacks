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
 * Must be deployed before kagent platform
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeNamespace } from '../../imports/k8s';

export interface KagentCrdsChartProps extends ChartProps {
  /**
   * kagent CRDs Helm chart version
   * @default '0.7.4'
   */
  version?: string;

  /**
   * Namespace for kagent components
   * @default 'kagent'
   */
  namespace?: string;
}

export class KagentCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props: KagentCrdsChartProps = {}) {
    super(scope, id, props);

    const version = props.version || '0.7.4';
    const ns = props.namespace || 'kagent';

    // Create namespace with very early sync wave
    new KubeNamespace(this, 'namespace', {
      metadata: {
        name: ns,
        labels: {
          'app.kubernetes.io/name': 'kagent',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // Deploy kagent CRDs using official Helm chart from OCI registry
    new Helm(this, 'kagent-crds', {
      chart: 'oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds',
      version: version,
      namespace: ns,
      releaseName: 'kagent-crds',
      values: {},
    });
  }
}
