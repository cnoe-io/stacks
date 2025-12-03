/**
 * ObservabilityNamespaceChart - Creates the observability namespace
 *
 * This chart creates the observability namespace for Jaeger and Langfuse.
 * Deploy order: sync wave -70 (before observability components)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface ObservabilityNamespaceChartProps extends ChartProps {
  /**
   * Name of the namespace
   * @default 'observability'
   */
  namespaceName?: string;
}

export class ObservabilityNamespaceChart extends Chart {
  constructor(scope: Construct, id: string, props?: ObservabilityNamespaceChartProps) {
    super(scope, id, props);

    const namespaceName = props?.namespaceName || 'observability';

    // Create observability namespace with sync wave annotation
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespaceName,
        labels: {
          'app.kubernetes.io/name': 'observability',
          'app.kubernetes.io/component': 'infrastructure',
          'app.kubernetes.io/part-of': 'observability',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
    });
  }
}
