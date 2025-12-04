import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * Props for K8sApiTailscaleServeChart
 */
export interface K8sApiTailscaleServeChartProps extends ChartProps {
  /**
   * Service name for Tailscale Services registration
   * @default 'k8s-api'
   */
  serviceName?: string;

  /**
   * Kubernetes namespace for deployment
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Name of the secret containing the Tailscale auth key
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Tailscale container image
   * @default 'tailscale/tailscale:latest'
   */
  tailscaleImage?: string;

  /**
   * kubectl container image
   * @default 'bitnami/kubectl:latest'
   */
  kubectlImage?: string;
}

/**
 * Expose Kubernetes API via Tailscale Services for remote kubectl access.
 *
 * This chart creates a deployment with:
 * 1. Tailscale container running in userspace mode with --service flag
 * 2. kubectl-proxy sidecar providing API access
 *
 * The kubectl proxy runs on port 8001 internally, but Tailscale serves it
 * on HTTPS port 443 with automatic TLS.
 *
 * Access: https://k8s-api.<tailnet>.ts.net/api/v1/...
 *
 * Usage:
 *   kubectl --server=https://k8s-api.<tailnet>.ts.net --token=<sa-token> get pods
 */
export class K8sApiTailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props?: K8sApiTailscaleServeChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace ?? 'tailscale';
    const serviceName = props?.serviceName ?? 'k8s-api';
    const authKeySecretName = props?.authKeySecretName ?? 'tailscale-auth-key';
    const tailscaleImage = props?.tailscaleImage ?? 'tailscale/tailscale:latest';
    const kubectlImage = props?.kubectlImage ?? 'bitnami/kubectl:latest';

    const deploymentName = 'k8s-api-tailscale-serve';

    // ServiceAccount for API access
    new k8s.KubeServiceAccount(this, 'sa', {
      metadata: {
        name: 'k8s-api-serve',
        namespace,
      },
    });

    // ClusterRoleBinding for cluster-admin access
    new k8s.KubeClusterRoleBinding(this, 'crb', {
      metadata: {
        name: 'k8s-api-tailscale-serve',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'cluster-admin',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'k8s-api-serve',
          namespace,
        },
      ],
    });

    // Deployment with Tailscale + kubectl-proxy
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: deploymentName,
        namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/part-of': 'kubernetes',
          'app.kubernetes.io/component': 'api-proxy',
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
            serviceAccountName: 'k8s-api-serve',
            containers: [
              {
                name: 'tailscale-serve',
                image: tailscaleImage,
                securityContext: {
                  runAsNonRoot: false,
                  privileged: false,
                },
                env: [
                  {
                    name: 'TS_AUTHKEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: authKeySecretName,
                        key: 'authKey',
                      },
                    },
                  },
                ],
                command: ['/bin/sh', '-c'],
                args: [generateK8sApiServeScript(serviceName)],
                ports: [
                  { name: 'https', containerPort: 443 },
                ],
              },
              {
                name: 'kubectl-proxy',
                image: kubectlImage,
                command: [
                  'kubectl',
                  'proxy',
                  '--port=8001',
                  '--address=0.0.0.0',
                  '--accept-hosts=.*',
                  '--reject-paths=^$',
                ],
                ports: [
                  { name: 'http', containerPort: 8001 },
                ],
                livenessProbe: {
                  httpGet: {
                    path: '/healthz',
                    port: k8s.IntOrString.fromNumber(8001),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/healthz',
                    port: k8s.IntOrString.fromNumber(8001),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                },
              },
            ],
          },
        },
      },
    });
  }
}

/**
 * Generate the shell script for the K8s API Tailscale serve container.
 *
 * Note: In userspace networking mode with Tailscale Services, netstack routes
 * incoming traffic to the exposed port (443), not the configured backend port.
 * We use socat to forward from 443 -> 8001 (kubectl-proxy).
 */
function generateK8sApiServeScript(serviceName: string): string {
  return `
set -euo pipefail

# start tailscaled in userspace mode (no TUN device needed)
mkdir -p /var/lib/tailscale
tailscaled --tun=userspace-networking \\
  --socket=/run/tailscale/tailscaled.sock \\
  --state=/var/lib/tailscale/tailscaled.state &

# install socat for port forwarding (required for userspace networking + Services)
apk add --no-cache socat >/dev/null

# wait for tailscaled to come up
for i in $(seq 1 40); do
  tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1 && break
  sleep 0.5
done

# bring the node up (no DNS/routes/ssh)
tailscale --socket=/run/tailscale/tailscaled.sock up \\
  --authkey="$TS_AUTHKEY" \\
  --accept-dns=false --accept-routes=false --ssh=false

# wait for kubectl-proxy to be ready
for i in $(seq 1 30); do
  wget -q -O /dev/null http://127.0.0.1:8001/healthz && break
  sleep 1
done

# Start socat to forward from exposed port (443) to kubectl-proxy (8001)
# This is required because netstack in userspace mode routes to the exposed port
socat TCP-LISTEN:443,fork,reuseaddr TCP:127.0.0.1:8001 &

# expose kubectl-proxy via tailscale serve on HTTPS 443
# The serve command tells Tailscale to route traffic to localhost:443 (socat)
tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve --service=svc:${serviceName} --https=443 http://127.0.0.1:443

echo "Kubernetes API proxy running at https://${serviceName}.<tailnet>.ts.net"
exec tail -f /dev/null
`;
}
