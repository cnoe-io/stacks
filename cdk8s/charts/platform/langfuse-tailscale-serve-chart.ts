/**
 * LangfuseTailscaleServeChart - Expose Langfuse UI via Tailscale Services
 * Feature: 102-bootstrap-talos-argocd
 *
 * This chart creates a deployment that:
 * - Runs Tailscale in userspace networking mode
 * - Exposes Langfuse server via Tailscale Services
 * - Provides HTTPS access with automatic TLS
 *
 * Access: https://<serviceName>.<tailnet>.ts.net
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface LangfuseTailscaleServeChartProps extends ChartProps {
  /**
   * Service name for Tailscale Services registration
   * @default 'langfuse'
   */
  serviceName?: string;

  /**
   * Kubernetes namespace for deployment
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Backend host for Langfuse server
   * @default 'langfuse.observability.svc.cluster.local'
   */
  backendHost?: string;

  /**
   * Backend port for Langfuse server
   * @default 3000
   */
  backendPort?: number;

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
   * kubectl container image (for init container)
   * @default 'bitnami/kubectl:latest'
   */
  kubectlImage?: string;
}

export class LangfuseTailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props: LangfuseTailscaleServeChartProps = {}) {
    super(scope, id, props);

    const {
      serviceName = 'langfuse',
      namespace = 'tailscale',
      backendHost = 'langfuse.observability.svc.cluster.local',
      backendPort = 3000,
      authKeySecretName = 'tailscale-auth-key',
      tailscaleImage = 'tailscale/tailscale:latest',
      kubectlImage = 'bitnami/kubectl:latest',
    } = props;

    const deploymentName = 'langfuse-tailscale-serve';
    const serviceAccountName = 'langfuse-tailscale-serve';

    // ServiceAccount for the deployment
    new k8s.KubeServiceAccount(this, 'sa', {
      metadata: {
        name: serviceAccountName,
        namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/component': 'proxy',
        },
      },
    });

    // Role to allow reading secrets (needed by init container)
    new k8s.KubeRole(this, 'secret-reader-role', {
      metadata: {
        name: `${deploymentName}-secret-reader`,
        namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/component': 'rbac',
        },
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // RoleBinding to bind the Role to the ServiceAccount
    new k8s.KubeRoleBinding(this, 'secret-reader-binding', {
      metadata: {
        name: `${deploymentName}-secret-reader`,
        namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/component': 'rbac',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: `${deploymentName}-secret-reader`,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccountName,
          namespace,
        },
      ],
    });

    // Deployment with Tailscale serve
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: deploymentName,
        namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/part-of': 'langfuse',
          'app.kubernetes.io/component': 'proxy',
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
            serviceAccountName,
            // Init container waits for auth key secret
            initContainers: [
              {
                name: 'wait-for-secret',
                image: kubectlImage,
                command: ['/bin/sh', '-c'],
                args: [`
echo "Waiting for secret ${authKeySecretName} to exist..."
while ! kubectl get secret ${authKeySecretName} -n ${namespace} > /dev/null 2>&1; do
  echo "Secret not found, waiting 5s..."
  sleep 5
done
echo "Secret ${authKeySecretName} found, proceeding..."
`],
              },
            ],
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
                args: [generateLangfuseServeScript(serviceName, backendHost, backendPort)],
                ports: [
                  { name: 'https', containerPort: 443 },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('50m'),
                    memory: k8s.Quantity.fromString('64Mi'),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('200m'),
                    memory: k8s.Quantity.fromString('256Mi'),
                  },
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
 * Generate the shell script for the Langfuse Tailscale serve container.
 *
 * Notes:
 * - Tailscale serve can only proxy to localhost, not remote hosts
 * - We use socat to forward from localhost to the Langfuse backend
 */
function generateLangfuseServeScript(
  serviceName: string,
  backendHost: string,
  backendPort: number
): string {
  return `
set -euo pipefail

# Start tailscaled in userspace mode (no TUN device needed)
mkdir -p /var/lib/tailscale
tailscaled --tun=userspace-networking \\
  --socket=/run/tailscale/tailscaled.sock \\
  --state=/var/lib/tailscale/tailscaled.state &

# Install required tools (socat for proxying, curl for health checks)
apk add --no-cache socat curl >/dev/null

# Wait for tailscaled to come up
for i in $(seq 1 40); do
  tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1 && break
  sleep 0.5
done

# Bring the node up (no DNS/routes/ssh)
tailscale --socket=/run/tailscale/tailscaled.sock up \\
  --authkey="$TS_AUTHKEY" \\
  --accept-dns=false --accept-routes=false --ssh=false

# Clear any stale serve configuration (PVC-backed state can survive pod reschedules)
tailscale --socket=/run/tailscale/tailscaled.sock serve reset || true

# Wait for Langfuse to be ready
echo "Waiting for Langfuse backend at http://${backendHost}:${backendPort}..."
for i in $(seq 1 60); do
  curl -s http://${backendHost}:${backendPort}/api/public/health >/dev/null && break
  sleep 2
done
echo "Langfuse backend is ready"

# Start socat to forward from localhost:8080 to Langfuse backend
# Tailscale serve only supports localhost proxies
echo "Starting socat proxy to ${backendHost}:${backendPort}..."
socat TCP-LISTEN:8080,fork,reuseaddr TCP:${backendHost}:${backendPort} &

# Wait for socat to be ready
sleep 1

# Expose via Tailscale Services (stable, predictable URL)
echo "Starting Tailscale serve for ${serviceName}..."
tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve --bg --service=svc:${serviceName} --https=443 http://127.0.0.1:8080

# Advertise as a Service host (required for approval/auto-approval)
tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve advertise svc:${serviceName} || echo "WARN: service host not yet approved (svc:${serviceName})"

echo "Service running at https://${serviceName}.<tailnet>.ts.net"
exec tail -f /dev/null
`;
}
