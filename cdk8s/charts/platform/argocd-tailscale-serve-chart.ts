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
  generateWaitForSecretInitContainer,
} from '../../lib/tailscale-serve-helpers';

/**
 * Expose ArgoCD over Tailscale using tailscale serve (userspace, no TUN).
 *
 * Supports two modes:
 * - Tailscale Services mode (default): Uses --service flag for stable service URLs
 * - Legacy hostname mode: Uses TS_HOSTNAME for device-based URLs (backward compatibility)
 *
 * Uses existing secret tailscale-auth-key in the tailscale namespace.
 *
 * Access (Tailscale Services mode): https://svc:argocd.<tailnet>.ts.net
 * Access (legacy mode): https://argocd-ui-serve.<tailnet>.ts.net
 */
export class ArgoCdTailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props?: TailscaleServeChartProps) {
    super(scope, id, props);

    // Apply defaults for backward compatibility when props not provided
    const defaultProps: TailscaleServeChartProps = {
      serviceName: 'argocd',
      backendHost: 'argocd-server.argocd.svc.cluster.local',
      backendPort: 443,
      backendInsecure: true, // ArgoCD uses self-signed certs
      ...props,
    };

    const resolvedProps = resolveProps(defaultProps);

    const namespace = resolvedProps.namespace;
    const name = 'argocd-tailscale-serve';
    // Uses shared ServiceAccount from TailscaleServeRbacChart
    const serviceAccountName = 'tailscale-serve';

    new k8s.KubeDeployment(this, 'ts-serve-deployment', {
      metadata: {
        name,
        namespace,
        labels: {
          'app.kubernetes.io/name': name,
          'app.kubernetes.io/part-of': 'argocd',
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
            serviceAccountName,
            // Init container waits for secret to exist before starting main container
            // This prevents CreateContainerConfigError when ESO hasn't synced yet
            initContainers: [generateWaitForSecretInitContainer(resolvedProps)],
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
