/**
 * GatewayApiCrdsChart - Deploys Kubernetes Gateway API CRDs v1.4.0
 *
 * This chart installs the standard Gateway API CRDs required by kgateway:
 * - GatewayClass
 * - Gateway
 * - HTTPRoute
 * - ReferenceGrant
 * - GRPCRoute
 * - TCPRoute
 * - TLSRoute
 * - UDPRoute
 *
 * Must be deployed before kgateway CRDs and kgateway
 */

import { Chart, ChartProps, Include } from 'cdk8s';
import { Construct } from 'constructs';

export interface GatewayApiCrdsChartProps extends ChartProps {
  /**
   * Gateway API version
   * @default 'v1.4.0'
   */
  version?: string;
}

export class GatewayApiCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props: GatewayApiCrdsChartProps = {}) {
    super(scope, id, props);

    const version = props.version || 'v1.4.0';

    // Include Gateway API standard CRDs from official release
    new Include(this, 'gateway-api-crds', {
      url: `https://github.com/kubernetes-sigs/gateway-api/releases/download/${version}/standard-install.yaml`,
    });
  }
}
