/**
 * Contract: Tailscale Serve Chart Properties
 *
 * This interface defines the contract for Tailscale serve chart configuration.
 * Used by ArgoCdTailscaleServeChart, LangfuseTailscaleServeChart, and future
 * service-specific charts.
 */

import { ChartProps } from 'cdk8s';

/**
 * Base properties for Tailscale serve deployments.
 * Enables configuration of services exposed via Tailscale Services (beta).
 */
export interface TailscaleServeChartProps extends ChartProps {
  /**
   * Service name for Tailscale Services registration.
   * Will be prefixed with 'svc:' when used with --service flag.
   *
   * @example 'argocd-ryzen' → --service=svc:argocd-ryzen
   * @example 'langfuse-thinkpad' → --service=svc:langfuse-thinkpad
   */
  serviceName: string;

  /**
   * Backend Kubernetes service URL within the cluster.
   * The Tailscale serve container will proxy traffic to this URL.
   *
   * @example 'argocd-server.argocd.svc.cluster.local'
   * @example 'langfuse.observability.svc.cluster.local'
   */
  backendHost: string;

  /**
   * Backend port to proxy to.
   *
   * @example 443 for ArgoCD
   * @example 3000 for Langfuse
   */
  backendPort: number;

  /**
   * Name of the Kubernetes Secret containing the Tailscale auth key.
   * The secret must have a key named 'authKey'.
   *
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Key within the secret that contains the auth key value.
   *
   * @default 'authKey'
   */
  authKeySecretKey?: string;

  /**
   * Namespace to deploy the Tailscale serve pod.
   *
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Port to expose via Tailscale HTTPS.
   * Maps to --https=<port> flag.
   *
   * @default 443
   */
  exposedPort?: number;

  /**
   * Whether the backend uses a self-signed or invalid certificate.
   * If true, uses https+insecure:// scheme for backend connection.
   *
   * @default false
   */
  backendInsecure?: boolean;

  /**
   * Protocol scheme for backend connection.
   * Inferred from backendInsecure if not specified.
   *
   * @default 'http' if backendInsecure is false
   * @default 'https+insecure' if backendInsecure is true
   */
  backendScheme?: 'http' | 'https' | 'https+insecure';

  /**
   * Tailscale container image.
   *
   * @default 'tailscale/tailscale:latest'
   */
  tailscaleImage?: string;

  /**
   * Enable legacy hostname mode (for backward compatibility).
   * If true, uses TS_HOSTNAME instead of --service flag.
   *
   * @default false
   * @deprecated Use serviceName for Tailscale Services
   */
  legacyHostnameMode?: boolean;

  /**
   * Legacy hostname for device registration.
   * Only used when legacyHostnameMode is true.
   *
   * @deprecated Use serviceName for Tailscale Services
   */
  legacyHostname?: string;
}

/**
 * Resolved/computed properties with defaults applied.
 * Internal use only - not part of public contract.
 */
export interface ResolvedTailscaleServeChartProps {
  serviceName: string;
  backendHost: string;
  backendPort: number;
  authKeySecretName: string;
  authKeySecretKey: string;
  namespace: string;
  exposedPort: number;
  backendScheme: 'http' | 'https' | 'https+insecure';
  tailscaleImage: string;
  legacyHostnameMode: boolean;
  legacyHostname?: string;
}

/**
 * Apply defaults to chart props.
 */
export function resolveProps(props: TailscaleServeChartProps): ResolvedTailscaleServeChartProps {
  const backendInsecure = props.backendInsecure ?? false;

  return {
    serviceName: props.serviceName,
    backendHost: props.backendHost,
    backendPort: props.backendPort,
    authKeySecretName: props.authKeySecretName ?? 'tailscale-auth-key',
    authKeySecretKey: props.authKeySecretKey ?? 'authKey',
    namespace: props.namespace ?? 'tailscale',
    exposedPort: props.exposedPort ?? 443,
    backendScheme: props.backendScheme ?? (backendInsecure ? 'https+insecure' : 'http'),
    tailscaleImage: props.tailscaleImage ?? 'tailscale/tailscale:latest',
    legacyHostnameMode: props.legacyHostnameMode ?? false,
    legacyHostname: props.legacyHostname,
  };
}
