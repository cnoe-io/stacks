/**
 * FeatureFlagsNamespaceChart - Creates the feature-flags namespace
 *
 * This chart creates the feature-flags namespace for flagd and Flipt.
 * Deploy order: sync wave -110 (before feature flag infrastructure)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface FeatureFlagsNamespaceChartProps extends ChartProps {
  /**
   * Name of the namespace
   * @default 'feature-flags'
   */
  namespaceName?: string;
}

export class FeatureFlagsNamespaceChart extends Chart {
  constructor(scope: Construct, id: string, props?: FeatureFlagsNamespaceChartProps) {
    super(scope, id, props);

    const namespaceName = props?.namespaceName || 'feature-flags';

    // Create feature-flags namespace with sync wave annotation
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespaceName,
        labels: {
          'app.kubernetes.io/name': 'feature-flags',
          'app.kubernetes.io/component': 'infrastructure',
          'app.kubernetes.io/part-of': 'feature-flags',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-110',
        },
      },
    });
  }
}
