/**
 * CDI (Containerized Data Importer) Operator Chart
 *
 * Deploys the CDI operator to the cluster.
 * CDI provides DataVolume resources for importing VM disk images.
 *
 * This chart deploys the upstream CDI operator from the v1.59.0 release.
 */

import { Chart, ChartProps, Include } from 'cdk8s';
import { Construct } from 'constructs';

export interface CDIOperatorChartProps extends ChartProps {
  /**
   * CDI version to deploy
   * @default "v1.59.0"
   */
  version?: string;
}

export class CDIOperatorChart extends Chart {
  constructor(scope: Construct, id: string, props: CDIOperatorChartProps = {}) {
    super(scope, id, props);

    const version = props.version || 'v1.59.0';

    // Deploy CDI operator from upstream release
    // This includes: operator deployment, RBAC, CRDs
    new Include(this, 'cdi-operator', {
      url: `https://github.com/kubevirt/containerized-data-importer/releases/download/${version}/cdi-operator.yaml`,
    });
  }
}
