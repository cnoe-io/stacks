import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';

/**
 * KGatewayCRDsChart deploys kgateway CRDs using Helm
 * This must be installed before the main kgateway controller
 */
export class KGatewayCRDsChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const namespace = 'kgateway-system';

    // Deploy kgateway CRDs using Helm chart
    new Helm(this, 'kgateway-crds', {
      chart: 'oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds',
      helmFlags: [
        '--namespace', namespace,
        '--create-namespace',
        '--version', 'v2.0.4', // Using stable release matching main controller
      ],
      values: {
        // CRD-specific configuration if needed
      },
    });
  }
}