/**
 * ApplicationConfig Schema Contract
 *
 * This defines the extended ApplicationConfig type with targetCluster support
 * for hub-and-spoke multi-cluster deployment.
 *
 * Location: cdk8s/lib/idpbuilder-types.ts
 * Usage: config/applications.ts entries
 */

/**
 * Target cluster specification for hub-and-spoke model
 */
export type TargetCluster =
  | 'hub' // Deploy to hub cluster (in-cluster)
  | 'hetzner' // Deploy to Hetzner spoke
  | 'thinkpad' // Deploy to Thinkpad spoke
  | 'ryzen' // Deploy to Ryzen spoke
  | 'talos' // Deploy to Talos spoke
  | string; // Any registered spoke cluster name

/**
 * Cluster type for synthesis filtering
 */
export type ClusterType = 'kind' | 'talos' | 'both';

/**
 * Chart configuration
 */
export interface ChartConfig {
  /**
   * Chart class name registered in IdpBuilderChartFactory
   * @example 'BackstageChart', 'KargoHelmChart', 'ArgocdClusterSecretChart'
   */
  type: string;

  /**
   * Chart-specific properties passed to constructor
   */
  props?: Record<string, unknown>;
}

/**
 * ArgoCD-specific configuration
 */
export interface ArgoCdConfig {
  /**
   * Sync wave for resource ordering
   * Lower numbers sync first
   * @example '-80', '0', '100'
   */
  syncWave?: string;

  /**
   * ArgoCD Application labels
   */
  labels?: Record<string, string>;

  /**
   * ArgoCD Application annotations
   */
  annotations?: Record<string, string>;

  /**
   * Sync policy configuration
   */
  syncPolicy?: {
    automated?: {
      prune?: boolean;
      selfHeal?: boolean;
      allowEmpty?: boolean;
    };
    syncOptions?: string[];
    retry?: {
      limit?: number;
      backoff?: {
        duration?: string;
        factor?: number;
        maxDuration?: string;
      };
    };
  };

  /**
   * Target cluster for deployment (hub-and-spoke model)
   *
   * - 'hub': Deploy to hub cluster only (in-cluster destination)
   * - spoke name: Deploy to specific spoke (e.g., 'thinkpad', 'talos')
   * - undefined: Use existing logic (vcluster for dev/staging, in-cluster otherwise)
   *
   * @example
   * targetCluster: 'hub'        // Management apps
   * targetCluster: 'thinkpad'   // Dev workloads
   * targetCluster: 'talos'      // Production workloads
   */
  targetCluster?: TargetCluster;

  /**
   * Ignored differences for sync comparison
   */
  ignoreDifferences?: Array<{
    group?: string;
    kind: string;
    name?: string;
    namespace?: string;
    jsonPointers?: string[];
    jqPathExpressions?: string[];
    managedFieldsManagers?: string[];
  }>;
}

/**
 * Application dependency reference
 */
export interface DependencyConfig {
  /**
   * Chart type to depend on
   */
  type: string;

  /**
   * Optional specific application name
   */
  name?: string;
}

/**
 * Extended ApplicationConfig with hub-and-spoke support
 */
export interface ApplicationConfig {
  /**
   * Unique application identifier
   * Used for ArgoCD Application name and package directory
   * @example 'backstage', 'kargo-pipelines-project', 'argocd-cluster-thinkpad'
   */
  name: string;

  /**
   * Target Kubernetes namespace for deployment
   * Created by ArgoCD if syncOptions includes CreateNamespace=true
   * @example 'backstage', 'argocd', 'kargo-pipelines'
   */
  namespace: string;

  /**
   * Skip this application during synthesis
   * Useful for temporarily disabling apps without removing config
   * @default false
   */
  disabled?: boolean;

  /**
   * Cluster type filter for synthesis
   * - 'kind': Only synthesize for KIND clusters (cnoe:// URLs)
   * - 'talos': Only synthesize for Talos clusters (GitHub URLs)
   * - 'both': Synthesize for all cluster types
   * @default 'both'
   */
  clusterType?: ClusterType;

  /**
   * Chart configuration
   */
  chart: ChartConfig;

  /**
   * ArgoCD-specific configuration including targetCluster
   */
  argocd?: ArgoCdConfig;

  /**
   * Application dependencies (resolved via sync waves)
   */
  dependencies?: Record<string, DependencyConfig>;
}

/**
 * Example configurations demonstrating hub-and-spoke patterns
 */
export const exampleConfigs: ApplicationConfig[] = [
  // Hub-only: Management application
  {
    name: 'kargo',
    namespace: 'kargo',
    chart: { type: 'KargoHelmChart' },
    argocd: {
      syncWave: '70',
      targetCluster: 'hub',
    },
  },

  // Hub-only: Spoke cluster registration
  {
    name: 'argocd-cluster-thinkpad',
    namespace: 'argocd',
    chart: {
      type: 'ArgocdClusterSecretChart',
      props: {
        clusterName: 'thinkpad',
        clusterServer: 'https://k8s-api-thinkpad.tail286401.ts.net',
      },
    },
    argocd: {
      syncWave: '-80',
      targetCluster: 'hub',
      labels: {
        'cluster-host': 'thinkpad',
        'cluster-type': 'development',
      },
    },
  },

  // Spoke-targeted: Development workload
  {
    name: 'backstage-dev',
    namespace: 'backstage',
    chart: {
      type: 'BackstageChart',
      props: { environment: 'dev' },
    },
    argocd: {
      syncWave: '100',
      targetCluster: 'thinkpad',
      labels: {
        'app.kubernetes.io/environment': 'dev',
        'kargo.akuity.io/loop': 'outer',
      },
      annotations: {
        'kargo.akuity.io/authorized-stage': 'kargo-pipelines:backstage-dev',
      },
    },
  },

  // Spoke-targeted: Production workload
  {
    name: 'backstage-prod',
    namespace: 'backstage',
    chart: {
      type: 'BackstageChart',
      props: { environment: 'production' },
    },
    argocd: {
      syncWave: '100',
      targetCluster: 'talos',
      labels: {
        'app.kubernetes.io/environment': 'production',
        'kargo.akuity.io/loop': 'outer',
      },
      annotations: {
        'kargo.akuity.io/authorized-stage': 'kargo-pipelines:backstage-prod',
      },
    },
  },
];

/**
 * Validation function for ApplicationConfig
 */
export function validateApplicationConfig(config: ApplicationConfig): string[] {
  const errors: string[] = [];

  // Required fields
  if (!config.name) {
    errors.push('name is required');
  }
  if (!config.namespace) {
    errors.push('namespace is required');
  }
  if (!config.chart?.type) {
    errors.push('chart.type is required');
  }

  // Name format validation
  if (config.name && !/^[a-z0-9-]+$/.test(config.name)) {
    errors.push('name must be lowercase alphanumeric with hyphens');
  }

  // Namespace format validation
  if (config.namespace && !/^[a-z0-9-]+$/.test(config.namespace)) {
    errors.push('namespace must be lowercase alphanumeric with hyphens');
  }

  // ClusterType validation
  if (config.clusterType && !['kind', 'talos', 'both'].includes(config.clusterType)) {
    errors.push('clusterType must be kind, talos, or both');
  }

  // TargetCluster validation (basic)
  if (config.argocd?.targetCluster) {
    const validTargets = ['hub', 'hetzner', 'thinkpad', 'ryzen', 'talos'];
    if (!validTargets.includes(config.argocd.targetCluster)) {
      // Allow custom spoke names but warn
      console.warn(`Custom targetCluster: ${config.argocd.targetCluster}`);
    }
  }

  return errors;
}
