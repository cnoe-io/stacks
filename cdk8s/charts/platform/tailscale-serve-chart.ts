/**
 * TailscaleServeChart - Exposes services via Tailscale Services for stable URLs
 *
 * This chart creates a Tailscale serve deployment using the --service flag pattern
 * for stable URLs that survive cluster recreation. This is the OPTIMAL implementation
 * per Constitution Principle V (Tailscale Services Standards).
 *
 * Key features:
 * - Stable service URLs (<name>.<tailnet>.ts.net)
 * - No hostname suffix drift (-1, -2, etc.)
 * - ACL auto-approvers with tag:k8s-services
 *
 * Let's Encrypt Rate Limits:
 * - 5 certificates per domain per 168 hours (7 days)
 * - 10 new registrations per IP per 3 hours
 * - Set persistentStorage: true to persist certificates across pod restarts
 * - Without persistent storage, uses emptyDir (certificates lost on pod restart)
 *
 * Prerequisites:
 * - Auth key with tag:k8s-services in Azure Key Vault
 * - ACL auto-approvers configured in Tailscale Admin Console
 * - tailscale-auth-key secret synced via ESO
 *
 * @see Constitution Principle V: Tailscale Services Standards
 * @see Constitution Principle IX: Forward-Only Development (no legacy hostname mode)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  TailscaleServeChartProps,
  resolveProps,
  generateServeScript,
} from '../../lib/tailscale-serve-helpers';

export { TailscaleServeChartProps } from '../../lib/tailscale-serve-helpers';

/**
 * Tailscale Serve Chart using Services mode for stable URLs.
 *
 * Access: https://<serviceName>.<tailnet>.ts.net
 *
 * @example
 * new TailscaleServeChart(app, 'argocd-serve', {
 *   serviceName: 'argocd',
 *   backendHost: 'argocd-server.argocd.svc.cluster.local',
 *   backendPort: 443,
 *   backendInsecure: true,
 * });
 */
export class TailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleServeChartProps) {
    super(scope, id, props);

    const resolved = resolveProps(props);
    const deploymentName = `${resolved.serviceName}-tailscale-serve`;
    const serviceAccountName = `${deploymentName}-sa`;
    const pvcName = `${deploymentName}-state`;

    // PersistentVolumeClaim for Tailscale state (when persistent storage is enabled)
    // This persists certificates and state across pod restarts to avoid Let's Encrypt rate limits
    if (resolved.persistentStorage) {
      new k8s.KubePersistentVolumeClaim(this, 'pvc', {
        metadata: {
          name: pvcName,
          namespace: resolved.namespace,
          labels: {
            'app.kubernetes.io/name': deploymentName,
            'app.kubernetes.io/component': 'tailscale-serve',
            'app.kubernetes.io/managed-by': 'cdk8s',
          },
        },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: {
            requests: {
              storage: k8s.Quantity.fromString(resolved.storageSize),
            },
          },
          ...(resolved.storageClassName && { storageClassName: resolved.storageClassName }),
        },
      });
    }

    // ServiceAccount for the deployment
    new k8s.KubeServiceAccount(this, 'service-account', {
      metadata: {
        name: serviceAccountName,
        namespace: resolved.namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/component': 'tailscale-serve',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // Role to allow reading secrets (for init container)
    new k8s.KubeRole(this, 'role', {
      metadata: {
        name: `${deploymentName}-role`,
        namespace: resolved.namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/component': 'tailscale-serve',
          'app.kubernetes.io/managed-by': 'cdk8s',
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

    // RoleBinding to bind the role to the service account
    new k8s.KubeRoleBinding(this, 'role-binding', {
      metadata: {
        name: `${deploymentName}-rolebinding`,
        namespace: resolved.namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/component': 'tailscale-serve',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: `${deploymentName}-role`,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccountName,
          namespace: resolved.namespace,
        },
      ],
    });

    // Deployment with Tailscale serve container
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: deploymentName,
        namespace: resolved.namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/component': 'tailscale-serve',
          'app.kubernetes.io/part-of': 'tailscale',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
      spec: {
        replicas: 1,
        // Avoid Rollout deadlocks on single-node KIND clusters at max pod capacity.
        // RollingUpdate defaults can require scheduling a surge pod first (maxSurge=25%),
        // which fails when the node is already at its pod limit.
        strategy: { type: 'Recreate' },
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': deploymentName,
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': deploymentName,
              'app.kubernetes.io/component': 'tailscale-serve',
            },
          },
          spec: {
            serviceAccountName: serviceAccountName,
            // Init container waits for auth key secret to exist
            initContainers: [
              {
                name: 'wait-for-secret',
                image: resolved.kubectlImage,
                command: ['/bin/sh', '-c'],
                args: [`
echo "Waiting for secret ${resolved.authKeySecretName} to exist..."
while ! kubectl get secret ${resolved.authKeySecretName} -n ${resolved.namespace} > /dev/null 2>&1; do
  echo "Secret not found, waiting 5s..."
  sleep 5
done
echo "Secret ${resolved.authKeySecretName} found, proceeding..."
`],
              },
            ],
            containers: [
              {
                name: 'tailscale-serve',
                image: resolved.tailscaleImage,
                securityContext: {
                  runAsNonRoot: false,
                  privileged: false,
                },
                env: [
                  {
                    name: 'TS_AUTHKEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: resolved.authKeySecretName,
                        key: resolved.authKeySecretKey,
                      },
                    },
                  },
                  {
                    name: 'BACKEND_HOST',
                    value: resolved.backendHost,
                  },
                  {
                    name: 'BACKEND_PORT',
                    value: String(resolved.backendPort),
                  },
                ],
                command: ['/bin/sh', '-c'],
                args: [generateServeScriptWithBackend(
                  resolved.serviceName,
                  resolved.backendHost,
                  resolved.backendPort,
                  resolved.backendInsecure
                )],
                ports: [
                  { name: 'https', containerPort: 443 },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('50m'),
                    memory: k8s.Quantity.fromString('128Mi'),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('200m'),
                    memory: k8s.Quantity.fromString('256Mi'),
                  },
                },
                volumeMounts: [
                  {
                    name: 'tailscale-state',
                    mountPath: '/var/lib/tailscale',
                  },
                ],
              },
            ],
            // Volume for Tailscale state - uses PVC when persistentStorage is enabled
            // otherwise uses emptyDir (state lost on pod restart)
            volumes: [
              resolved.persistentStorage
                ? {
                    name: 'tailscale-state',
                    persistentVolumeClaim: {
                      claimName: pvcName,
                    },
                  }
                : {
                    name: 'tailscale-state',
                    emptyDir: {},
                  },
            ],
          },
        },
      },
    });
  }
}

/**
 * Generate serve script with backend service forwarding.
 *
 * This script:
 * 1. Starts tailscaled in userspace mode
 * 2. Authenticates with the auth key
 * 3. Sets up socat to forward traffic to the backend service
 * 4. Registers with Tailscale Services via --service flag
 *
 * @param serviceName - Tailscale service name (e.g., 'argocd')
 * @param backendHost - Backend service hostname
 * @param backendPort - Backend service port
 * @param backendInsecure - Whether to skip TLS verification for backend
 */
function generateServeScriptWithBackend(
  serviceName: string,
  backendHost: string,
  backendPort: number,
  backendInsecure: boolean
): string {
  // For backend health check - use http for insecure backends, https for secure
  const backendScheme = backendInsecure ? 'http' : (backendPort === 443 ? 'https' : 'http');
  // backendInsecure is kept for health check scheme but no longer affects serve config
  // Tailscale serve always uses http:// to socat, which does raw TCP forwarding
  void backendInsecure; // Explicitly mark as intentionally unused for serve scheme

  return `
set -euo pipefail

# Start tailscaled in userspace mode (no TUN device needed)
mkdir -p /var/lib/tailscale
tailscaled --tun=userspace-networking \\
  --socket=/run/tailscale/tailscaled.sock \\
  --state=/var/lib/tailscale/tailscaled.state &

# Install socat for port forwarding (required for userspace networking + Services)
apk add --no-cache socat >/dev/null 2>&1 || true

# Wait for tailscaled to come up
for i in $(seq 1 40); do
  tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1 && break
  sleep 0.5
done

# Bring the node up with service registration
tailscale --socket=/run/tailscale/tailscaled.sock up \\
  --authkey="$TS_AUTHKEY" \\
  --accept-dns=false --accept-routes=false --ssh=false

# Clear any stale serve configuration (PVC-backed state can survive pod reschedules)
tailscale --socket=/run/tailscale/tailscaled.sock serve reset || true

# Wait for backend service to be reachable
echo "Waiting for backend service ${backendHost}:${backendPort}..."
for i in $(seq 1 60); do
  if wget -q --spider --timeout=2 ${backendScheme}://${backendHost}:${backendPort}/ 2>/dev/null || \\
     wget -q --spider --timeout=2 ${backendScheme}://${backendHost}:${backendPort}/healthz 2>/dev/null || \\
     nc -z -w2 ${backendHost} ${backendPort} 2>/dev/null; then
    echo "Backend service is reachable"
    break
  fi
  echo "Waiting for backend... ($i/60)"
  sleep 2
done

# Start socat to forward from internal port (8080) to backend service
# NOTE: socat does raw TCP forwarding - it doesn't speak TLS
# The backend service handles TLS termination if needed
socat TCP-LISTEN:8080,fork,reuseaddr TCP:${backendHost}:${backendPort} &

# Expose via Tailscale Services (stable, predictable URL)
# Tailscale serve terminates TLS and forwards plain HTTP to socat on port 8080
# socat then forwards raw TCP to the backend (which may re-establish TLS)
tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve --bg --service=svc:${serviceName} --https=443 http://127.0.0.1:8080

# Advertise as a Service host (required for approval/auto-approval)
tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve advertise svc:${serviceName} || echo "WARN: service host not yet approved (svc:${serviceName})"

echo "Service running at https://${serviceName}.<tailnet>.ts.net"
echo "Backend: ${backendHost}:${backendPort}"

# Keep container running
exec tail -f /dev/null
`;
}
