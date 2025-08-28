import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { Bash } from 'cdk8s';

/**
 * GatewayAPICRDsChart installs the Kubernetes Gateway API CRDs
 * These are required before installing kgateway
 */
export class GatewayAPICRDsChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    // Install Gateway API CRDs v1.2.0 (stable release)
    // Using Include to fetch and apply the CRDs
    new Bash(this, 'gateway-api-crds', {
      command: `curl -sL https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml | kubectl apply -f -`,
    });
  }
}