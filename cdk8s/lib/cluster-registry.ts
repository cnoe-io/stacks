/**
 * Cluster Registry: Hub-and-Spoke Model
 *
 * Provides type-safe spoke cluster definitions and helpers for
 * ArgoCD multi-cluster deployments via Tailscale mesh network.
 */

/**
 * Known spoke cluster names in the hub-and-spoke model
 */
export type SpokeClusterName = 'hetzner' | 'thinkpad' | 'ryzen' | 'talos';

/**
 * Target cluster for ArgoCD Application destination
 * - 'hub': Deploy to hub cluster (in-cluster destination)
 * - SpokeClusterName: Deploy to specific spoke cluster
 */
export type TargetCluster = 'hub' | SpokeClusterName;

/**
 * Spoke cluster environment classification
 */
export type ClusterEnvironment = 'development' | 'staging' | 'production';

/**
 * Spoke cluster configuration
 */
export interface SpokeClusterConfig {
  /** Cluster name (matches ArgoCD cluster secret name) */
  name: SpokeClusterName;
  /** Human-readable display name */
  displayName: string;
  /** Kubernetes API URL via Tailscale */
  serverUrl: string;
  /** Environment classification */
  environment: ClusterEnvironment;
  /** Additional metadata labels */
  labels?: Record<string, string>;
}

/**
 * Tailnet configuration for service URLs
 */
export const TAILNET_NAME = 'tail286401';

/**
 * Generate Tailscale k8s-api service URL for a cluster
 */
export function getK8sApiUrl(clusterName: string): string {
  return `https://k8s-api-${clusterName}.${TAILNET_NAME}.ts.net`;
}

/**
 * Generate ArgoCD service URL for hub
 */
export function getArgoCdHubUrl(): string {
  return `https://argocd-hub.${TAILNET_NAME}.ts.net`;
}

/**
 * Registry of all known spoke clusters
 */
export const SPOKE_CLUSTERS: Record<SpokeClusterName, SpokeClusterConfig> = {
  hetzner: {
    name: 'hetzner',
    displayName: 'Hetzner Production',
    serverUrl: getK8sApiUrl('hetzner'),
    environment: 'production',
    labels: {
      'cluster-host': 'hetzner',
      'cluster-type': 'production',
    },
  },
  thinkpad: {
    name: 'thinkpad',
    displayName: 'Thinkpad Development',
    serverUrl: getK8sApiUrl('thinkpad'),
    environment: 'development',
    labels: {
      'cluster-host': 'thinkpad',
      'cluster-type': 'development',
    },
  },
  ryzen: {
    name: 'ryzen',
    displayName: 'Ryzen Staging',
    serverUrl: getK8sApiUrl('ryzen'),
    environment: 'staging',
    labels: {
      'cluster-host': 'ryzen',
      'cluster-type': 'staging',
    },
  },
  talos: {
    name: 'talos',
    displayName: 'Talos Production',
    serverUrl: getK8sApiUrl('talos'),
    environment: 'production',
    labels: {
      'cluster-host': 'talos',
      'cluster-type': 'production',
    },
  },
};

/**
 * Get all spoke cluster names
 */
export function getSpokeClusterNames(): SpokeClusterName[] {
  return Object.keys(SPOKE_CLUSTERS) as SpokeClusterName[];
}

/**
 * Get spoke cluster config by name
 */
export function getSpokeCluster(name: SpokeClusterName): SpokeClusterConfig {
  return SPOKE_CLUSTERS[name];
}

/**
 * Check if a string is a valid spoke cluster name
 */
export function isSpokeCluster(name: string): name is SpokeClusterName {
  return name in SPOKE_CLUSTERS;
}

/**
 * Get Azure Key Vault secret names for spoke credentials
 */
export function getAzureKeyVaultSecretNames(spokeName: SpokeClusterName): {
  tokenKey: string;
  caKey: string;
} {
  const upperName = spokeName.toUpperCase();
  return {
    tokenKey: `ARGOCD-CLUSTER-${upperName}-TOKEN`,
    caKey: `ARGOCD-CLUSTER-${upperName}-CA`,
  };
}

/**
 * Generate ArgoCD cluster secret name for a spoke
 */
export function getClusterSecretName(spokeName: SpokeClusterName): string {
  return `cluster-${spokeName}`;
}

/**
 * Generate ExternalSecret name for spoke credentials
 */
export function getExternalSecretName(spokeName: SpokeClusterName): string {
  return `argocd-cluster-${spokeName}`;
}
