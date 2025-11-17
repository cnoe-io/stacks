/**
 * KgatewayCrdsChart - Deploys kgateway CRDs via Helm chart
 *
 * This chart installs the Custom Resource Definitions required by kgateway:
 * - GatewayParameters
 * - Upstream
 * - DirectResponse
 * - RouteOption
 * - VirtualHostOption
 * - HttpListenerOption
 * - ListenerOption
 * - GatewayContextExtension
 *
 * Must be deployed after Gateway API CRDs and before kgateway
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';

export interface KgatewayCrdsChartProps extends ChartProps {
  /**
   * kgateway CRDs Helm chart version
   * @default 'v2.1.1'
   */
  version?: string;
}

export class KgatewayCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props: KgatewayCrdsChartProps = {}) {
    super(scope, id, props);

    const version = props.version || 'v2.1.1';

    // Deploy kgateway CRDs using official Helm chart from OCI registry
    new Helm(this, 'kgateway-crds', {
      chart: 'oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds',
      version: version,
      releaseName: 'kgateway-crds',
      values: {},
    });
  }
}
