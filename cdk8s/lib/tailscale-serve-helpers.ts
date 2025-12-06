import { ChartProps } from 'cdk8s';

/**
 * Tailscale Serve Chart Props Interface
 *
 * Configuration interface for Tailscale serve deployments using Services mode.
 * Used by all platform serve charts (ArgoCD, Langfuse, Gitea, etc.)
 *
 * @see Constitution Principle V: Tailscale Services Standards
 */

/**
 * Props for Tailscale serve charts using Services mode
 *
 * @example
 * const props: TailscaleServeChartProps = {
 *   serviceName: 'argocd',
 *   backendHost: 'argocd-server.argocd.svc.cluster.local',
 *   backendPort: 443,
 *   backendInsecure: true
 * };
 */
export interface TailscaleServeChartProps extends ChartProps {
  /**
   * Service name for Tailscale Services registration.
   * Will be prefixed with 'svc:' for registration and 'svc-' for URL.
   *
   * @example 'argocd' → svc:argocd → https://svc-argocd.<tailnet>.ts.net
   */
  serviceName: string;

  /**
   * Kubernetes service hostname to proxy traffic to.
   * Must be fully qualified cluster DNS name.
   *
   * @example 'argocd-server.argocd.svc.cluster.local'
   */
  backendHost: string;

  /**
   * Backend service port number.
   *
   * @example 443 for HTTPS backends, 3000 for HTTP backends
   */
  backendPort: number;

  /**
   * Name of the Kubernetes Secret containing the Tailscale auth key.
   *
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Key name within the secret containing the auth key value.
   *
   * @default 'authKey'
   */
  authKeySecretKey?: string;

  /**
   * Namespace for the Tailscale serve deployment.
   *
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * HTTPS port to expose via Tailscale Services.
   *
   * @default 443
   */
  exposedPort?: number;

  /**
   * Whether the backend uses self-signed certificates.
   * When true, adds '+insecure' to the serve configuration.
   *
   * @default false
   */
  backendInsecure?: boolean;

  /**
   * Tailscale container image to use.
   *
   * @default 'tailscale/tailscale:latest'
   */
  tailscaleImage?: string;

  /**
   * kubectl container image to use for init containers.
   *
   * @default 'bitnami/kubectl:latest'
   */
  kubectlImage?: string;

  /**
   * Enable persistent storage for Tailscale state.
   * When true, creates a PVC for /var/lib/tailscale to persist certificates
   * across pod restarts, avoiding Let's Encrypt rate limits.
   *
   * @default false (uses emptyDir)
   */
  persistentStorage?: boolean;

  /**
   * Storage size for the persistent volume claim.
   * Only used when persistentStorage is true.
   *
   * @default '1Gi'
   */
  storageSize?: string;

  /**
   * Storage class name for the persistent volume claim.
   * Only used when persistentStorage is true.
   * If not specified, uses the cluster default storage class.
   *
   * @default undefined (uses cluster default)
   */
  storageClassName?: string;
}

/**
 * Resolved props with all defaults applied
 */
export interface ResolvedTailscaleServeChartProps {
  serviceName: string;
  backendHost: string;
  backendPort: number;
  authKeySecretName: string;
  authKeySecretKey: string;
  namespace: string;
  exposedPort: number;
  backendInsecure: boolean;
  tailscaleImage: string;
  kubectlImage: string;
  persistentStorage: boolean;
  storageSize: string;
  storageClassName?: string;
  /**
   * Computed backend URL scheme based on backendInsecure flag
   * 'http+insecure' when backendInsecure=true, 'https' otherwise
   */
  backendScheme: string;
  /**
   * Full service registration name with svc: prefix
   * @example 'svc:argocd'
   */
  serviceRegistration: string;
  /**
   * Full backend URL for tailscale serve command
   * @example 'http+insecure://argocd-server.argocd.svc.cluster.local:443'
   */
  backendUrl: string;
}

/**
 * Resolve TailscaleServeChartProps with defaults
 *
 * @param props - Input props with optional fields
 * @returns Fully resolved props with all defaults applied
 */
export function resolveProps(props: TailscaleServeChartProps): ResolvedTailscaleServeChartProps {
  const authKeySecretName = props.authKeySecretName ?? 'tailscale-auth-key';
  const authKeySecretKey = props.authKeySecretKey ?? 'authKey';
  const namespace = props.namespace ?? 'tailscale';
  const exposedPort = props.exposedPort ?? 443;
  const backendInsecure = props.backendInsecure ?? false;
  const tailscaleImage = props.tailscaleImage ?? 'tailscale/tailscale:latest';
  const kubectlImage = props.kubectlImage ?? 'bitnami/kubectl:latest';
  const persistentStorage = props.persistentStorage ?? false;
  const storageSize = props.storageSize ?? '1Gi';
  const storageClassName = props.storageClassName;

  // Compute derived values
  const backendScheme = backendInsecure ? 'http+insecure' : 'https';
  const serviceRegistration = `svc:${props.serviceName}`;
  const backendUrl = `${backendScheme}://${props.backendHost}:${props.backendPort}`;

  return {
    serviceName: props.serviceName,
    backendHost: props.backendHost,
    backendPort: props.backendPort,
    authKeySecretName,
    authKeySecretKey,
    namespace,
    exposedPort,
    backendInsecure,
    tailscaleImage,
    kubectlImage,
    persistentStorage,
    storageSize,
    storageClassName,
    backendScheme,
    serviceRegistration,
    backendUrl,
  };
}

/**
 * Generate the shell script for Tailscale serve container.
 *
 * This is the OPTIMAL pattern extracted from k8s-api-tailscale-serve-chart.ts.
 * Uses Tailscale Services (--service flag) for stable URLs.
 *
 * Key implementation details:
 * - Userspace networking mode (no TUN device needed in containers)
 * - socat for port forwarding (required for userspace networking + Services)
 * - --service flag for stable service registration
 *
 * @param serviceName - Service name (e.g., 'argocd')
 * @param backendPort - Backend service port to forward to
 * @returns Shell script for Tailscale container
 */
export function generateServeScript(serviceName: string, backendPort: number): string {
  return `
set -euo pipefail

# Start tailscaled in userspace mode (no TUN device needed)
mkdir -p /var/lib/tailscale
tailscaled --tun=userspace-networking \\
  --socket=/run/tailscale/tailscaled.sock \\
  --state=/var/lib/tailscale/tailscaled.state &

# Install socat for port forwarding (required for userspace networking + Services)
apk add --no-cache socat >/dev/null

# Wait for tailscaled to come up
for i in $(seq 1 40); do
  tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1 && break
  sleep 0.5
done

# Bring the node up with service registration
tailscale --socket=/run/tailscale/tailscaled.sock up \\
  --authkey="$TS_AUTHKEY" \\
  --accept-dns=false --accept-routes=false --ssh=false

# Wait for backend service to be ready (try healthz first, then root)
for i in $(seq 1 30); do
  wget -q -O /dev/null http://127.0.0.1:${backendPort}/healthz 2>/dev/null || \\
    wget -q -O /dev/null http://127.0.0.1:${backendPort}/ 2>/dev/null && break
  sleep 1
done

# Start socat to forward from exposed port (443) to backend port
# This is required because netstack in userspace mode routes to the exposed port
socat TCP-LISTEN:443,fork,reuseaddr TCP:127.0.0.1:${backendPort} &

# Expose via Tailscale serve on HTTPS 443 with service registration
tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve --service=svc:${serviceName} --https=443 http://127.0.0.1:443

echo "Service running at https://svc-${serviceName}.<tailnet>.ts.net"
exec tail -f /dev/null
`;
}

/**
 * Service configurations for all platform services
 *
 * NOTE: Service names use "2" suffix to bypass Let's Encrypt rate limits.
 * This can be reverted to base names (argocd, langfuse, etc.) once rate limits reset.
 *
 * URLs: https://<serviceName>.tail286401.ts.net
 *
 * Let's Encrypt Rate Limits (Tailscale hardcodes production endpoint):
 * - 5 certificates per domain per 168 hours (7 days)
 * - 10 new registrations per IP per 3 hours
 * - Solution: Use PVC for /var/lib/tailscale to persist certificates across restarts
 * - No paid Tailscale plan exemption (limits from Let's Encrypt, not Tailscale)
 *
 * @see data-model.md Service Configuration Matrix
 * @see applications.ts for actual deployment configuration
 */
export const PLATFORM_SERVICES: Record<string, Omit<TailscaleServeChartProps, keyof ChartProps>> = {
  argocd: {
    serviceName: 'argocd2',  // Using argocd2 to bypass Let's Encrypt rate limit
    backendHost: 'argocd-server.argocd.svc.cluster.local',
    backendPort: 443,
    backendInsecure: true,
  },
  langfuse: {
    serviceName: 'langfuse2',  // Using langfuse2 to bypass Let's Encrypt rate limit
    backendHost: 'langfuse.observability.svc.cluster.local',
    backendPort: 3000,
    backendInsecure: false,
  },
  gitea: {
    serviceName: 'gitea2',  // Using gitea2 to bypass Let's Encrypt rate limit
    backendHost: 'my-gitea-http.gitea.svc.cluster.local',
    backendPort: 3000,
    backendInsecure: false,
  },
  kagent: {
    serviceName: 'kagent2',  // Using kagent2 to bypass Let's Encrypt rate limit
    backendHost: 'kagent-ui.kagent.svc.cluster.local',
    backendPort: 8080,
    backendInsecure: false,
  },
  kargo: {
    serviceName: 'kargo2',  // Using kargo2 to bypass Let's Encrypt rate limit
    backendHost: 'kargo-api.kargo.svc.cluster.local',
    backendPort: 80,
    backendInsecure: false,
  },
  headlamp: {
    serviceName: 'headlamp2',  // Using headlamp2 to bypass Let's Encrypt rate limit
    backendHost: 'headlamp.headlamp.svc.cluster.local',
    backendPort: 80,
    backendInsecure: false,
  },
  keycloak: {
    serviceName: 'keycloak2',  // Using keycloak2 to bypass Let's Encrypt rate limit
    backendHost: 'keycloak.keycloak.svc.cluster.local',
    backendPort: 8080,
    backendInsecure: false,
  },
};
