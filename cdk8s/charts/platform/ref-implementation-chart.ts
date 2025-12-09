/**
 * RefImplementationChart - Generates ArgoCD Applications for ref-implementation packages
 * Feature: 106-consolidate-bootstrap-between
 *
 * This chart allows reusing CNOE ref-implementation packages in Talos clusters
 * by converting cnoe:// URLs to GitHub URLs pointing to ref-implementation/.
 *
 * Supports:
 * - Local manifests (cnoe:// style pointing to ref-implementation/<package>/manifests)
 * - External Helm charts (metric-server, spark-operator)
 * - Kustomize overlays (argo-workflows with dev/prod paths)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  Application,
  ApplicationSpec,
  ApplicationSpecSyncPolicy,
} from '../../imports/argoproj.io';

/**
 * Source types supported by ref-implementation packages
 */
export type RefImplSourceType = 'manifests' | 'helm' | 'kustomize';

/**
 * Helm chart configuration for external Helm sources
 */
export interface HelmSourceConfig {
  repoURL: string;
  chart: string;
  targetRevision: string;
  values?: string;
  valuesObject?: Record<string, any>;
}

/**
 * Props for RefImplementationChart
 */
export interface RefImplementationChartProps extends ChartProps {
  /**
   * Package name (e.g., 'keycloak', 'metric-server')
   */
  packageName: string;

  /**
   * Target namespace for deployment
   */
  targetNamespace: string;

  /**
   * Source type
   * @default 'manifests'
   */
  sourceType?: RefImplSourceType;

  /**
   * Path within ref-implementation/<package>/ directory
   * @default 'manifests'
   */
  manifestPath?: string;

  /**
   * Helm configuration (required if sourceType is 'helm')
   */
  helm?: HelmSourceConfig;

  /**
   * Git repository URL
   * @default process.env.GIT_REPO_URL or 'https://github.com/PittampalliOrg/stacks.git'
   */
  gitRepoUrl?: string;

  /**
   * Git branch/revision
   * @default process.env.GIT_BRANCH or 'main'
   */
  gitBranch?: string;

  /**
   * ArgoCD sync wave for deployment ordering
   */
  syncWave?: string;

  /**
   * Additional labels for the Application
   */
  labels?: Record<string, string>;

  /**
   * Additional annotations for the Application
   */
  annotations?: Record<string, string>;

  /**
   * Sync policy configuration
   */
  syncPolicy?: ApplicationSpecSyncPolicy;

  /**
   * Whether to create namespace if it doesn't exist
   * @default true
   */
  createNamespace?: boolean;
}

/**
 * Chart that generates ArgoCD Applications for ref-implementation packages
 */
export class RefImplementationChart extends Chart {
  public readonly application: Application;

  constructor(scope: Construct, id: string, props: RefImplementationChartProps) {
    super(scope, id, props);

    const {
      packageName,
      targetNamespace,
      sourceType = 'manifests',
      manifestPath = 'manifests',
      helm,
      gitRepoUrl = process.env.GIT_REPO_URL || 'https://github.com/PittampalliOrg/stacks.git',
      gitBranch = process.env.GIT_BRANCH || 'main',
      syncWave,
      labels = {},
      annotations = {},
      syncPolicy,
      createNamespace = true,
    } = props;

    // Validate helm config for helm source type
    if (sourceType === 'helm' && !helm) {
      throw new Error(`RefImplementationChart: helm configuration required for sourceType 'helm'`);
    }

    // Build metadata
    const metadata = this.buildMetadata(packageName, syncWave, labels, annotations);

    // Build spec based on source type
    const spec = this.buildSpec({
      packageName,
      targetNamespace,
      sourceType,
      manifestPath,
      helm,
      gitRepoUrl,
      gitBranch,
      syncPolicy,
      createNamespace,
    });

    // Create the Application
    this.application = new Application(this, 'application', {
      metadata,
      spec,
    });
  }

  /**
   * Build Application metadata
   */
  private buildMetadata(
    packageName: string,
    syncWave?: string,
    labels: Record<string, string> = {},
    annotations: Record<string, string> = {}
  ): any {
    const metadata: any = {
      name: packageName,
      namespace: 'argocd',
      labels: {
        'app.kubernetes.io/managed-by': 'cdk8s',
        'app.kubernetes.io/name': packageName,
        'app.kubernetes.io/part-of': 'ref-implementation',
        'app.kubernetes.io/component': 'platform',
        example: 'basic',
        ...labels,
      },
      finalizers: ['resources-finalizer.argocd.argoproj.io'],
    };

    const allAnnotations: Record<string, string> = { ...annotations };
    if (syncWave) {
      allAnnotations['argocd.argoproj.io/sync-wave'] = syncWave;
    }
    if (Object.keys(allAnnotations).length > 0) {
      metadata.annotations = allAnnotations;
    }

    return metadata;
  }

  /**
   * Build Application spec based on source type
   */
  private buildSpec(config: {
    packageName: string;
    targetNamespace: string;
    sourceType: RefImplSourceType;
    manifestPath: string;
    helm?: HelmSourceConfig;
    gitRepoUrl: string;
    gitBranch: string;
    syncPolicy?: ApplicationSpecSyncPolicy;
    createNamespace: boolean;
  }): ApplicationSpec {
    const {
      packageName,
      targetNamespace,
      sourceType,
      manifestPath,
      helm,
      gitRepoUrl,
      gitBranch,
      syncPolicy,
      createNamespace,
    } = config;

    // Build source based on type
    let source: any;

    if (sourceType === 'helm' && helm) {
      // External Helm chart
      source = {
        repoUrl: helm.repoURL,
        chart: helm.chart,
        targetRevision: helm.targetRevision,
      };

      if (helm.values || helm.valuesObject) {
        source.helm = {};
        if (helm.values) {
          source.helm.values = helm.values;
        } else if (helm.valuesObject) {
          source.helm.values = this.objectToYaml(helm.valuesObject);
        }
      }
    } else {
      // Git-based source (manifests or kustomize)
      source = {
        repoUrl: gitRepoUrl,
        path: `ref-implementation/${packageName}/${manifestPath}`,
        targetRevision: gitBranch,
      };
    }

    // Build sync options
    const syncOptions: string[] = [];
    if (createNamespace) {
      syncOptions.push('CreateNamespace=true');
    }

    // Default sync policy
    const defaultSyncPolicy: ApplicationSpecSyncPolicy = {
      automated: {
        selfHeal: true,
        prune: true,
      },
      syncOptions: syncOptions.length > 0 ? syncOptions : undefined,
    };

    return {
      project: 'default',
      source,
      destination: {
        server: 'https://kubernetes.default.svc',
        namespace: targetNamespace,
      },
      syncPolicy: syncPolicy || defaultSyncPolicy,
    } as ApplicationSpec;
  }

  /**
   * Convert an object to YAML string for Helm values
   */
  private objectToYaml(obj: Record<string, any>, indent: number = 0): string {
    const lines: string[] = [];
    const prefix = '  '.repeat(indent);

    for (const [key, value] of Object.entries(obj)) {
      if (value === null || value === undefined) {
        lines.push(`${prefix}${key}: null`);
      } else if (typeof value === 'object' && !Array.isArray(value)) {
        lines.push(`${prefix}${key}:`);
        lines.push(this.objectToYaml(value, indent + 1));
      } else if (Array.isArray(value)) {
        lines.push(`${prefix}${key}:`);
        for (const item of value) {
          if (typeof item === 'object') {
            lines.push(`${prefix}- `);
            lines.push(this.objectToYaml(item, indent + 2));
          } else {
            lines.push(`${prefix}- ${item}`);
          }
        }
      } else if (typeof value === 'string') {
        // Quote strings that might be interpreted as other types
        if (value.includes(':') || value.includes('#') || value === '') {
          lines.push(`${prefix}${key}: "${value}"`);
        } else {
          lines.push(`${prefix}${key}: ${value}`);
        }
      } else {
        lines.push(`${prefix}${key}: ${value}`);
      }
    }

    return lines.join('\n');
  }
}
