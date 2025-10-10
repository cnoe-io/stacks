/**
 * TailscaleCrdsChart - Deploys Tailscale CRDs via Helm chart
 *
 * This chart installs the Custom Resource Definitions required by Tailscale Operator:
 * - ProxyGroup
 * - ProxyClass
 * - Connector
 * - DNSConfig
 * - Recorder
 *
 * Must be deployed before TailscaleOperatorChart
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeNamespace } from '../../imports/k8s';

export class TailscaleCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const ns = 'tailscale';

    // Create namespace with very early sync wave
    new KubeNamespace(this, 'namespace', {
      metadata: {
        name: ns,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-120',
        },
        labels: {
          'app.kubernetes.io/name': 'tailscale',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // Deploy Tailscale Operator with only CRDs (no operator deployment)
    // We'll use hooks to install CRDs only
    new Helm(this, 'tailscale-crds', {
      chart: 'tailscale-operator',
      helmExecutable: 'helm',
      helmFlags: [
        '--repo', 'https://pkgs.tailscale.com/helmcharts',
      ],
      namespace: ns,
      releaseName: 'tailscale-crds',
      values: {
        // Install only CRDs, disable operator deployment
        operatorConfig: {
          image: {
            repo: 'tailscale/k8s-operator',
            tag: 'latest',
          },
        },
        // Set replicas to 0 so operator doesn't run (we only want CRDs)
        replicaCount: 0,
        // Ensure CRDs are installed
        installCRDs: true,
      },
    });
  }
}
