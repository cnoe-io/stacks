/**
 * Tailscale Serve Chart Props Interface
 *
 * Configuration interface for Tailscale serve deployments using Services mode.
 * Used by all platform serve charts (ArgoCD, Langfuse, Gitea, etc.)
 *
 * @see Constitution Principle V: Tailscale Services Standards
 */

import { ChartProps } from 'cdk8s';

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
   * Will be prefixed with 'svc:' for service identity (ACLs/auto-approvers).
   * URL format is `https://<serviceName>.<tailnet>.ts.net`.
   *
   * @example 'argocd-ryzen' → svc:argocd-ryzen → https://argocd-ryzen.<tailnet>.ts.net
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
}

/**
 * Resolved props with all defaults applied
 */
export interface ResolvedTailscaleServeChartProps extends Required<Omit<TailscaleServeChartProps, keyof ChartProps>> {
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

# Wait for backend service to be ready
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

echo "Service running at https://${serviceName}.<tailnet>.ts.net"
exec tail -f /dev/null
`;
}

/**
 * Service configurations for all platform services
 *
 * @see data-model.md Service Configuration Matrix
 */
export const PLATFORM_SERVICES: Record<string, Omit<TailscaleServeChartProps, keyof ChartProps>> = {
  argocd: {
    serviceName: 'argocd',
    backendHost: 'argocd-server.argocd.svc.cluster.local',
    backendPort: 443,
    backendInsecure: true,
  },
  langfuse: {
    serviceName: 'langfuse',
    backendHost: 'langfuse.langfuse.svc.cluster.local',
    backendPort: 3000,
    backendInsecure: false,
  },
  gitea: {
    serviceName: 'gitea',
    backendHost: 'gitea-http.gitea.svc.cluster.local',
    backendPort: 3000,
    backendInsecure: false,
  },
  kagent: {
    serviceName: 'kagent',
    backendHost: 'kagent-dashboard.kagent.svc.cluster.local',
    backendPort: 8082,
    backendInsecure: false,
  },
  kargo: {
    serviceName: 'kargo',
    backendHost: 'kargo-controller.kargo.svc.cluster.local',
    backendPort: 443,
    backendInsecure: true,
  },
  headlamp: {
    serviceName: 'headlamp',
    backendHost: 'headlamp.headlamp.svc.cluster.local',
    backendPort: 4466,
    backendInsecure: false,
  },
  keycloak: {
    serviceName: 'keycloak',
    backendHost: 'keycloak.keycloak.svc.cluster.local',
    backendPort: 8080,
    backendInsecure: false,
  },
};
