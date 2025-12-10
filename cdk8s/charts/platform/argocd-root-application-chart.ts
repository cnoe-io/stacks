/**
 * ArgoCDRootApplicationChart - App-of-Apps Root Application for Talos Bootstrap
 * Feature: 102-bootstrap-talos-argocd
 *
 * This chart creates the root ArgoCD Application that:
 * - Points to the directory containing all child Application manifests
 * - Enables cascading GitOps management of the entire platform
 * - Is applied after ArgoCD is installed via Helm
 *
 * Pattern: App-of-Apps (https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  Application,
  ApplicationSpec,
  ApplicationSpecDestination,
  ApplicationSpecSyncPolicy,
} from '../../imports/argoproj.io';

export interface ArgoCDRootApplicationChartProps extends ChartProps {
  /**
   * Git repository URL for ArgoCD to sync from
   */
  repoUrl: string;

  /**
   * Path in repository containing Application manifests
   * @default 'cdk8s/dist/talos'
   */
  path?: string;

  /**
   * Git reference (branch, tag, or commit)
   * @default 'main'
   */
  targetRevision?: string;

  /**
   * ArgoCD project to use
   * @default 'default'
   */
  project?: string;

  /**
   * Root application name
   * @default 'argocd-bootstrap'
   */
  applicationName?: string;

  /**
   * Enable automated sync with prune
   * @default true
   */
  enableAutomatedSync?: boolean;

  /**
   * Enable self-heal (auto-sync on drift)
   * @default true
   */
  enableSelfHeal?: boolean;

  /**
   * Enable prune (delete resources removed from Git)
   * @default true
   */
  enablePrune?: boolean;

  /**
   * Sync wave for the root application
   * @default '0'
   */
  syncWave?: string;

  /**
   * Additional labels to add
   */
  labels?: Record<string, string>;

  /**
   * Additional annotations to add
   */
  annotations?: Record<string, string>;
}

export class ArgoCDRootApplicationChart extends Chart {
  private readonly application: Application;

  constructor(scope: Construct, id: string, props: ArgoCDRootApplicationChartProps) {
    super(scope, id, props);

    const {
      repoUrl,
      path = 'cdk8s/dist/talos',
      targetRevision = 'main',
      project = 'default',
      applicationName = 'argocd-bootstrap',
      enableAutomatedSync = true,
      enableSelfHeal = true,
      enablePrune = true,
      syncWave = '0',
      labels = {},
      annotations = {},
    } = props;

    // Build metadata
    const metadata: Record<string, unknown> = {
      name: applicationName,
      namespace: 'argocd',
      labels: {
        'app.kubernetes.io/managed-by': 'cdk8s',
        'app.kubernetes.io/name': applicationName,
        'app.kubernetes.io/component': 'bootstrap',
        'app.kubernetes.io/part-of': 'platform',
        ...labels,
      },
      annotations: {
        'argocd.argoproj.io/sync-wave': syncWave,
        ...annotations,
      },
      finalizers: ['resources-finalizer.argocd.argoproj.io'],
    };

    // Build destination
    const destination: ApplicationSpecDestination = {
      server: 'https://kubernetes.default.svc',
      namespace: 'argocd', // Root app manages other Applications in argocd namespace
    };

    // Build sync policy
    const syncPolicy: ApplicationSpecSyncPolicy = {
      automated: enableAutomatedSync
        ? {
            prune: enablePrune,
            selfHeal: enableSelfHeal,
          }
        : undefined,
      syncOptions: [
        'CreateNamespace=true',
        'ServerSideApply=true',
        'PrunePropagationPolicy=foreground',
      ],
    };

    // Build spec
    const spec: ApplicationSpec = {
      project,
      source: {
        repoUrl,
        path,
        targetRevision,
        directory: {
          recurse: true,
          // Include only Application YAML files (not manifests subdirs)
          include: '*.yaml',
        },
      },
      destination,
      syncPolicy,
      // Ignore differences in Application status (managed by ArgoCD)
      ignoreDifferences: [
        {
          group: 'argoproj.io',
          kind: 'Application',
          jsonPointers: ['/status'],
        },
      ],
    };

    // Create the root Application
    this.application = new Application(this, 'root-application', {
      metadata,
      spec,
    });
  }

  /**
   * Get the generated Application resource
   */
  public getApplication(): Application {
    return this.application;
  }
}

/**
 * Factory function to create a root application with common defaults
 */
export function createRootApplication(
  scope: Construct,
  repoUrl: string,
  options: Partial<ArgoCDRootApplicationChartProps> = {}
): ArgoCDRootApplicationChart {
  return new ArgoCDRootApplicationChart(scope, 'root-app', {
    repoUrl,
    ...options,
  });
}
