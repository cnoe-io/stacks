/**
 * TailscaleCrdsChart - Deploys Tailscale CRDs
 *
 * This chart installs the Custom Resource Definitions required by Tailscale Operator:
 * - ProxyGroup
 * - ProxyClass
 * - Connector
 * - DNSConfig
 * - Recorder
 *
 * Must be deployed before TailscaleOperatorChart
 *
 * Note: We import the CRDs from cdk8s.yaml which sources them from
 * crds/tailscale-crds.yaml (extracted from official Helm chart)
 */

import { Chart, ChartProps, Include } from 'cdk8s';
import { Construct } from 'constructs';
import * as path from 'path';

export class TailscaleCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    // Include the Tailscale CRDs from the crds directory
    // These CRDs are extracted from the official Tailscale Helm chart
    // and imported into our TypeScript types via cdk8s.yaml
    new Include(this, 'tailscale-crds', {
      url: path.join(__dirname, '../../crds/tailscale-crds.yaml'),
    });
  }
}
