/**
 * Centralized ArgoCD Source URL Generation
 * Feature: 106-consolidate-bootstrap-between
 *
 * Provides unified source URL generation for ArgoCD Applications across
 * KIND (local idpBuilder) and Talos (GitHub) cluster types.
 *
 * Constitution Alignment:
 * - Principle II (GitOps-First): Cluster-type-driven ArgoCD sources
 * - Principle IX (Unified Bootstrap): CLUSTER_TYPE environment variable
 */

/**
 * Supported cluster types
 */
export type ClusterType = 'kind' | 'talos';

/**
 * ArgoCD Application source configuration
 */
export interface ApplicationSource {
  /**
   * Repository URL (cnoe:// for KIND, GitHub URL for Talos)
   */
  repoURL: string;

  /**
   * Path within the repository (only for Talos/Git sources)
   */
  path?: string;

  /**
   * Target revision/branch (only for Talos/Git sources)
   */
  targetRevision?: string;
}

/**
 * Get the cluster type from environment variable with validation.
 *
 * @returns The validated cluster type
 * @throws Error if CLUSTER_TYPE is set to an unsupported value
 */
export function getClusterType(): ClusterType {
  const clusterType = process.env.CLUSTER_TYPE;

  if (!clusterType) {
    console.warn('⚠ CLUSTER_TYPE not set, defaulting to "kind"');
    return 'kind';
  }

  if (clusterType !== 'kind' && clusterType !== 'talos') {
    throw new Error(
      `Unsupported CLUSTER_TYPE: ${clusterType}. Supported values: kind, talos`
    );
  }

  return clusterType;
}

/**
 * Generate ArgoCD Application source URL based on cluster type.
 *
 * For KIND clusters (local development):
 * - Uses cnoe://<appName>/manifests protocol
 * - idpBuilder automatically resolves to Gitea repository
 *
 * For Talos clusters (production):
 * - Uses GitHub repository URL from GIT_REPO_URL environment variable
 * - Includes path to manifests and branch from GIT_BRANCH
 *
 * @param appName - Name of the application (used in path)
 * @param clusterType - Target cluster type
 * @returns ApplicationSource configuration for ArgoCD
 */
export function getSourceUrl(
  appName: string,
  clusterType: ClusterType
): ApplicationSource {
  if (clusterType === 'kind') {
    // For KIND clusters, use cnoe:// protocol (idpBuilder resolves to Gitea)
    return {
      repoURL: `cnoe://${appName}/manifests`,
    };
  }

  // For Talos clusters, use GitHub repository with rendered branch
  // The rendered manifests workflow pushes to rendered/talos/<source-branch>
  const gitUrl =
    process.env.GIT_REPO_URL || 'https://github.com/PittampalliOrg/stacks.git';
  const sourceBranch = process.env.GIT_BRANCH || 'main';

  // Use rendered branch pattern: rendered/<cluster-type>/<source-branch>
  const renderedBranch = `rendered/talos/${sourceBranch}`;

  return {
    repoURL: gitUrl,
    path: `cdk8s/dist/${appName}/manifests`,
    targetRevision: renderedBranch,
  };
}

/**
 * Validate required environment variables for the given cluster type.
 *
 * @param clusterType - Target cluster type
 * @returns True if all required environment variables are set
 * @throws Error with descriptive message if validation fails
 */
export function validateEnvironmentForCluster(clusterType: ClusterType): boolean {
  const errors: string[] = [];

  if (clusterType === 'talos') {
    // Talos requires Git repository URL and Azure credentials
    const required = [
      'GIT_REPO_URL',
      'AZURE_CLIENT_ID',
      'AZURE_TENANT_ID',
      'AZURE_KEYVAULT_NAME',
    ];

    for (const varName of required) {
      if (!process.env[varName]) {
        errors.push(`Missing required environment variable for Talos: ${varName}`);
      }
    }

    // Warn about optional variables
    const optional = ['GIT_BRANCH', 'AZURE_STORAGE_ACCOUNT', 'TAILSCALE_TAILNET'];
    for (const varName of optional) {
      if (!process.env[varName]) {
        console.warn(`⚠ Optional environment variable not set: ${varName}`);
      }
    }
  }

  // KIND has fewer requirements - just uses cnoe:// protocol
  // Azure credentials are optional for workload identity

  if (errors.length > 0) {
    throw new Error(
      `Environment validation failed:\n${errors.map((e) => `  - ${e}`).join('\n')}`
    );
  }

  return true;
}

/**
 * Get the output directory for synthesized manifests based on cluster type.
 *
 * @param clusterType - Target cluster type
 * @returns Output directory path
 */
export function getOutputDir(clusterType: ClusterType): string {
  // Both cluster types now use the same output directory
  // The ArgoCD Application source URLs differentiate the behavior
  return 'dist';
}

/**
 * Check if an application should be synthesized for the given cluster type.
 *
 * @param appClusterType - Application's cluster type setting ('kind', 'talos', or 'both')
 * @param targetClusterType - The target cluster type for synthesis
 * @returns True if the application should be included
 */
export function shouldIncludeApp(
  appClusterType: 'kind' | 'talos' | 'both' | undefined,
  targetClusterType: ClusterType
): boolean {
  // Default to 'kind' for backward compatibility if not specified
  const effectiveAppType = appClusterType || 'kind';

  return effectiveAppType === 'both' || effectiveAppType === targetClusterType;
}
