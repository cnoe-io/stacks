import { Chart } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  TailscaleServeChartProps,
  resolveProps,
} from '../../lib/tailscale-serve-chart-props';
import {
  generateTailscaleServeScript,
  generateTailscaleEnvVars,
} from '../../lib/tailscale-serve-helpers';

/**
 * Extended props for the generic TailscaleServeChart
 */
export interface GenericTailscaleServeChartProps extends TailscaleServeChartProps {
  /**
   * Deployment name suffix (e.g., 'gitea' results in 'gitea-tailscale-serve')
   */
  deploymentName?: string;

  /**
   * Label for app.kubernetes.io/part-of
   */
  partOf?: string;
}

/**
 * Generic Tailscale Serve Chart for exposing any service via Tailscale Services.
 *
 * This chart creates a deployment that:
 * 1. Runs tailscaled in userspace mode
 * 2. Uses socat to proxy traffic to the backend service
 * 3. Registers as a Tailscale Service for stable URLs
 *
 * Access: https://<serviceName>.<tailnet>.ts.net
 */
export class TailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props: GenericTailscaleServeChartProps) {
    super(scope, id, props);

    const resolvedProps = resolveProps(props);

    const namespace = resolvedProps.namespace;
    const deploymentName = props.deploymentName || `${props.serviceName}-tailscale-serve`;
    const partOf = props.partOf || props.serviceName;

    new k8s.KubeDeployment(this, 'ts-serve-deployment', {
      metadata: {
        name: deploymentName,
        namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/part-of': partOf,
          'app.kubernetes.io/component': 'tailscale-serve',
        },
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: { 'app.kubernetes.io/name': deploymentName } },
        template: {
          metadata: {
            labels: { 'app.kubernetes.io/name': deploymentName },
          },
          spec: {
            automountServiceAccountToken: false,
            containers: [
              {
                name: 'tailscale-serve',
                image: resolvedProps.tailscaleImage,
                securityContext: {
                  runAsNonRoot: false,
                  privileged: false,
                },
                env: generateTailscaleEnvVars(resolvedProps),
                command: ['/bin/sh', '-c'],
                args: [generateTailscaleServeScript(resolvedProps)],
                ports: [
                  { name: 'https', containerPort: 443 },
                ],
              },
            ],
          },
        },
      },
    });
  }
}
