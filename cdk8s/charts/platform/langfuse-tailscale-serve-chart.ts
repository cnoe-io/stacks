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
 * Expose Langfuse over Tailscale using tailscale serve (userspace, no TUN).
 *
 * Supports two modes:
 * - Tailscale Services mode (default): Uses --service flag for stable service URLs
 * - Legacy hostname mode: Uses TS_HOSTNAME for device-based URLs (backward compatibility)
 *
 * Uses existing secret tailscale-auth-key in the tailscale namespace.
 *
 * Access (Tailscale Services mode): https://svc:langfuse.<tailnet>.ts.net
 * Access (legacy mode): https://langfuse.<tailnet>.ts.net
 */
export class LangfuseTailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props?: TailscaleServeChartProps) {
    super(scope, id, props);

    // Apply defaults for langfuse service
    // Langfuse runs on HTTP port 3000, so we use http:// scheme
    const defaultProps: TailscaleServeChartProps = {
      serviceName: 'langfuse',
      backendHost: 'langfuse.observability.svc.cluster.local',
      backendPort: 3000,
      backendInsecure: false,
      backendScheme: 'http',
      ...props,
    };

    const resolvedProps = resolveProps(defaultProps);

    const namespace = resolvedProps.namespace;
    const name = 'langfuse-tailscale-serve';

    new k8s.KubeDeployment(this, 'ts-serve-deployment', {
      metadata: {
        name,
        namespace,
        labels: {
          'app.kubernetes.io/name': name,
          'app.kubernetes.io/part-of': 'langfuse',
        },
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: { 'app.kubernetes.io/name': name } },
        template: {
          metadata: {
            labels: { 'app.kubernetes.io/name': name },
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
                  { name: 'peerapi', containerPort: 443 },
                ],
              },
            ],
          },
        },
      },
    });
  }
}
