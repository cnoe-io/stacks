/**
 * Contract: Tailscale CDK8s Chart Properties
 * Feature: 102-bootstrap-talos-argocd
 *
 * Defines the TypeScript interfaces for Tailscale-related CDK8s charts.
 */

import { ChartProps } from 'cdk8s';

/**
 * Properties for the Tailscale Operator Helm Chart
 */
export interface TailscaleOperatorChartProps extends ChartProps {
  /**
   * Helm chart version to install
   * @default '1.76.1'
   */
  version?: string;

  /**
   * Operator deployment namespace
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Hostname for the operator device in Tailscale
   * @default 'kind-operator'
   */
  hostname?: string;

  /**
   * Enable API server proxy mode for kubectl access
   * @default true
   */
  enableApiServerProxy?: boolean;

  /**
   * Enable high availability with ProxyGroup
   * @default false (for dev clusters)
   */
  enableHA?: boolean;

  /**
   * Device tags for ACL management
   * @default ['tag:k8s-operator']
   */
  tags?: string[];

  /**
   * OAuth secret name (created by ExternalSecret)
   * @default 'operator-oauth'
   */
  oauthSecretName?: string;

  /**
   * Sync wave for ordering (after secrets)
   * @default '-75'
   */
  syncWave?: string;

  /**
   * Additional Helm values to merge
   */
  additionalValues?: Record<string, unknown>;
}

/**
 * Properties for Tailscale Service exposure (serve mode)
 */
export interface TailscaleServeChartProps extends ChartProps {
  /**
   * Tailscale service name (e.g., 'argocd' -> svc:argocd)
   */
  serviceName: string;

  /**
   * Backend Kubernetes service host
   * Format: {service}.{namespace}.svc.cluster.local
   */
  backendHost: string;

  /**
   * Backend service port
   */
  backendPort: number;

  /**
   * Skip TLS verification for backend (for self-signed certs)
   * @default false
   */
  backendInsecure?: boolean;

  /**
   * Auth key secret name
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Namespace for the serve pod
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Enable legacy hostname mode instead of services
   * @default false
   */
  legacyHostnameMode?: boolean;

  /**
   * Legacy hostname (only if legacyHostnameMode is true)
   */
  legacyHostname?: string;

  /**
   * Sync wave for ordering
   * @default '-60'
   */
  syncWave?: string;
}

/**
 * Properties for Kubernetes API access via Tailscale
 */
export interface K8sApiTailscaleServeChartProps extends TailscaleServeChartProps {
  /**
   * Service name for K8s API
   * @default 'k8s-api'
   */
  serviceName?: string;

  /**
   * Backend host for K8s API
   * @default 'kubernetes.default.svc.cluster.local'
   */
  backendHost?: string;

  /**
   * Backend port for K8s API
   * @default 443
   */
  backendPort?: number;

  /**
   * Enable kubectl-proxy sidecar
   * @default true
   */
  enableKubectlProxy?: boolean;

  /**
   * kubectl-proxy listen port
   * @default 8001
   */
  kubectlProxyPort?: number;
}

/**
 * Properties for ArgoCD exposure via Tailscale
 */
export interface ArgoCDTailscaleServeChartProps extends TailscaleServeChartProps {
  /**
   * Service name for ArgoCD
   * @default 'argocd'
   */
  serviceName?: string;

  /**
   * Backend host for ArgoCD server
   * @default 'argocd-server.argocd.svc.cluster.local'
   */
  backendHost?: string;

  /**
   * Backend port for ArgoCD server
   * @default 443
   */
  backendPort?: number;

  /**
   * Skip TLS verification (ArgoCD uses self-signed by default)
   * @default true
   */
  backendInsecure?: boolean;
}

/**
 * Properties for Tailscale Secrets ExternalSecret
 */
export interface TailscaleSecretsChartProps extends ChartProps {
  /**
   * ClusterSecretStore name
   * @default 'azure-keyvault-store'
   */
  secretStoreName?: string;

  /**
   * Target secret name for auth key
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Target secret name for OAuth credentials
   * @default 'operator-oauth'
   */
  oauthSecretName?: string;

  /**
   * Refresh interval for secrets
   * @default '24h'
   */
  refreshInterval?: string;

  /**
   * Sync wave for ordering (before operator)
   * @default '-85'
   */
  syncWave?: string;
}

/**
 * Tailscale service URL patterns
 */
export const TAILSCALE_SERVICE_URLS = {
  /**
   * Generate ArgoCD service URL
   * @param tailnet Tailnet domain (e.g., 'tail286401')
   */
  argocd: (tailnet: string) => `svc-argocd.${tailnet}.ts.net`,

  /**
   * Generate K8s API service URL
   * @param tailnet Tailnet domain
   */
  k8sApi: (tailnet: string) => `svc-k8s-api.${tailnet}.ts.net`,

  /**
   * Generate custom service URL
   * @param serviceName Service name
   * @param tailnet Tailnet domain
   */
  custom: (serviceName: string, tailnet: string) =>
    `svc-${serviceName}.${tailnet}.ts.net`,
} as const;

/**
 * ACL configuration for Tailscale Services
 */
export interface TailscaleACLConfig {
  /**
   * Tag owners for k8s-services tag
   */
  tagOwners: {
    'tag:k8s-services': string[];
  };

  /**
   * Auto-approvers for service registration
   */
  autoApprovers: {
    services: {
      [serviceName: string]: string[];
    };
  };
}

/**
 * Example ACL configuration for bootstrap
 */
export const TAILSCALE_BOOTSTRAP_ACL: TailscaleACLConfig = {
  tagOwners: {
    'tag:k8s-services': ['autogroup:admin'],
  },
  autoApprovers: {
    services: {
      'svc:argocd': ['tag:k8s-services'],
      'svc:k8s-api': ['tag:k8s-services'],
      'svc:langfuse': ['tag:k8s-services'],
    },
  },
};
