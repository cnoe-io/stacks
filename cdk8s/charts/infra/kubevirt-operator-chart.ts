/**
 * KubeVirt Operator Chart
 *
 * Deploys the KubeVirt operator to the cluster.
 * The operator manages KubeVirt custom resources and deploys controllers/handlers.
 *
 * This chart deploys the upstream KubeVirt operator from the v1.3.1 release.
 */

import { Chart, ChartProps, Include } from 'cdk8s';
import { Construct } from 'constructs';

export interface KubeVirtOperatorChartProps extends ChartProps {
  /**
   * KubeVirt version to deploy
   * @default "v1.3.1"
   */
  version?: string;
}

export class KubeVirtOperatorChart extends Chart {
  constructor(scope: Construct, id: string, props: KubeVirtOperatorChartProps = {}) {
    super(scope, id, props);

    const version = props.version || 'v1.3.1';

    // Deploy KubeVirt operator from upstream release
    // This includes: operator deployment, RBAC, CRDs
    new Include(this, 'kubevirt-operator', {
      url: `https://github.com/kubevirt/kubevirt/releases/download/${version}/kubevirt-operator.yaml`,
    });
  }
}
