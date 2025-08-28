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

    // Deploy kgateway using Helm chart with AgentGateway enabled
    new Helm(this, 'kgateway', {
      chart: 'oci://cr.kgateway.dev/kgateway-dev/charts/kgateway',
      helmFlags: [
        '--namespace', namespace,
        '--create-namespace',
        '--version', 'v2.1.0-main', // Updated to support AgentGateway, MCP, and A2A
      ],
      values: {
        // Enable AgentGateway for MCP and A2A support
        agentGateway: {
          enabled: true,
        },
        // Enable inference extension for AI features
        inferenceExtension: {
          enabled: true,
        },
      },
    });
  }
}