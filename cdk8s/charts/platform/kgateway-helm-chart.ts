import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';

/**
 * KGatewayHelmChart deploys kgateway controller using Helm
 * This is the core component that manages Gateway API resources
 */
export class KGatewayHelmChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const namespace = 'kgateway-system';

    // Deploy kgateway using Helm chart with minimal configuration
    // The chart will use its own defaults which are properly configured
    new Helm(this, 'kgateway', {
      chart: 'oci://cr.kgateway.dev/kgateway-dev/charts/kgateway',
      helmFlags: [
        '--namespace', namespace,
        '--create-namespace',
        '--version', 'v2.0.4', // Using stable release
      ],
      values: {
        // Minimal configuration - let the chart use its defaults
        // which are properly configured for the image paths
      },
    });
  }
}