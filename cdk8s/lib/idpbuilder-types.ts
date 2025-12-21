import { ChartProps } from 'cdk8s';
import { TargetCluster } from './cluster-registry';

/**
 * Cluster type for filtering applications during synthesis
 * - 'kind': Only deploy to KIND (local development) clusters
 * - 'talos': Only deploy to Talos (production) clusters
 * - 'both': Deploy to both cluster types
 */
export type AppClusterType = 'kind' | 'talos' | 'both';

// Re-export TargetCluster for convenience
export type { TargetCluster } from './cluster-registry';

/**
 * Configuration for an IDPBuilder application package
 */
export interface ApplicationConfig {
  /**
   * Application name (used for package directory and ArgoCD app name)
   */
  name: string;

  /**
   * Target Kubernetes namespace
   */
  namespace: string;

  /**
   * Cluster type filter - determines which clusters this app is synthesized for.
   * - 'kind': Only KIND clusters (local development with idpBuilder)
   * - 'talos': Only Talos clusters (production with GitHub source)
   * - 'both': Both cluster types (shared infrastructure like ESO, Tailscale)
   * @default 'kind' for backward compatibility
   */
  clusterType?: AppClusterType;

  /**
   * Optional cluster-name filter for synthesis.
   *
   * If set, the app is only synthesized when the current cluster identity matches
   * one of these values. The current identity is determined by:
   *  - `CLUSTER_NAME` (preferred, deterministic in CI/GitOps)
   *  - falling back to `CLUSTER_HOST` (legacy/kind convenience)
   *
   * This is intended for cases where certain apps should only exist on specific
   * clusters (e.g., heavy workloads, host-bound experiments).
   */
  clusterNames?: string[];

  /**
   * Source path override for ArgoCD Application.
   * Use this for applications that reference existing directories (like 'entities')
   * instead of CDK8s-synthesized 'manifests'.
   * @default 'manifests'
   */
  sourcePath?: string;

  /**
   * Skip chart synthesis. Set to true for applications that reference
   * existing directories (like backstage-templates) rather than synthesized manifests.
   * @default false
   */
  skipSynthesis?: boolean;

  /**
   * Directory exclude pattern for ArgoCD directory source.
   * Used to exclude certain files from sync (e.g., 'catalog-info.yaml').
   */
  directoryExclude?: string;

  /**
   * Chart configuration
   */
  chart?: {
    /**
     * Chart class name (must be registered with factory)
     */
    type: string;
    
    /**
     * Chart-specific properties
     */
    props?: Record<string, any>;
  };
  
  /**
   * Optional dependencies for this chart
   */
  dependencies?: {
    [key: string]: {
      type: string;
      props?: Record<string, any>;
    };
  };
  
  /**
   * ArgoCD-specific configuration
   */
  argocd?: {
    /**
     * Target cluster for deployment (hub-and-spoke model)
     * - 'hub': Deploy to hub cluster only (in-cluster destination)
     * - spoke name: Deploy to specific spoke cluster (e.g., 'hetzner', 'thinkpad')
     * - undefined: Use existing logic (vcluster for dev/staging, in-cluster otherwise)
     */
    targetCluster?: TargetCluster;

    /**
     * Sync wave annotation
     */
    syncWave?: string;

    /**
     * Extra metadata annotations for the ArgoCD Application
     */
    annotations?: Record<string, string>;
    
    /**
     * Additional labels for the ArgoCD application
     */
    labels?: Record<string, string>;
    
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
     * Ignore differences configuration
     */
    ignoreDifferences?: Array<{
      group?: string;
      kind: string;
      name?: string;
      jsonPointers?: string[];
    }>;
    
    /**
     * Multi-source configuration for ArgoCD applications
     * If provided, will use 'sources' instead of 'source' in the Application spec
     */
    sources?: Array<{
      /**
       * Repository URL (Git or Helm)
       */
      repoURL: string;
      
      /**
       * Path within the repository (for Git sources)
       */
      path?: string;
      
      /**
       * Target revision (for Git sources)
       */
      targetRevision?: string;
      
      /**
       * Helm chart name (for Helm sources)
       */
      chart?: string;
      
      /**
       * Helm configuration
       */
      helm?: {
        valueFiles?: string[];
        values?: string;
        parameters?: Array<{
          name: string;
          value: string;
        }>;
      };
      
      /**
       * Reference name for multi-source apps
       */
      ref?: string;
    }>;
  };
}

/**
 * Chart constructor type for factory registration
 */
export type ChartConstructor = new (
  scope: any,
  id: string,
  props?: any
) => any;

/**
 * Enhanced ChartProps with potential dependencies
 */
export interface ChartPropsWithDependencies extends ChartProps {
  [key: string]: any;
}
