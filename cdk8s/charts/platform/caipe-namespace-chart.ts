/**
 * CaipeNamespaceChart - Creates the ai-platform-engineering namespace
 *
 * This chart creates the namespace for all CAIPE components with proper
 * labels and annotations for ArgoCD sync wave ordering.
 *
 * Must be deployed before any other CAIPE components.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface CaipeNamespaceChartProps extends ChartProps {
  /**
   * Namespace name
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '-110'
   */
  syncWave?: string;
}

export class CaipeNamespaceChart extends Chart {
  public readonly namespaceName: string;

  constructor(scope: Construct, id: string, props: CaipeNamespaceChartProps = {}) {
    super(scope, id, props);

    this.namespaceName = props.namespace || 'ai-platform-engineering';
    const syncWave = props.syncWave || '-110';

    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: this.namespaceName,
        labels: {
          'app.kubernetes.io/name': 'caipe',
          'app.kubernetes.io/part-of': 'ai-platform-engineering',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
    });
  }
}
