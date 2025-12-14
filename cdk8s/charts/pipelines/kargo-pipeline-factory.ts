import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  createWarehouse,
  createStage,
  ImageSubscriptionConfig,
  REGISTRY,
  TAG_PATTERNS,
  IGNORE_TAGS,
} from '../../lib/kargo-helpers';
import { WarehouseSpecSubscriptionsImageImageSelectionStrategy } from '../../imports/kargo.akuity.io';

/**
 * Configuration for a single stage in the pipeline
 */
export interface StageDefinition {
  /** Stage name (will be prefixed with app name) */
  name: string;
  /** Is this an inner loop stage? */
  isInnerLoop?: boolean;
  /** Get freight directly from warehouse (true) or from upstream stage (false) */
  directFromWarehouse?: boolean;
  /** Upstream stage name (when directFromWarehouse is false) */
  upstreamStage?: string;
  /** Required soak time in upstream stage */
  requiredSoakTime?: string;
  /** Auto-promote to this stage? */
  autoPromote?: boolean;
  /** ArgoCD application name (defaults to <app>-<stage>) */
  argocdAppName?: string;
  /** Is this a placeholder stage? */
  isPlaceholder?: boolean;
}

/**
 * Configuration for creating a complete Kargo pipeline
 */
export interface PipelineConfig {
  /** Application name (e.g., 'backstage', 'frontend') */
  appName: string;
  /** Namespace for Kargo resources (default: 'kargo-pipelines') */
  namespace?: string;

  // Inner Loop Configuration
  /** Enable inner loop (Gitea → local-dev) */
  enableInnerLoop?: boolean;
  /** Gitea registry URL (default: gitea.cnoe.localtest.me:8443/giteaadmin) */
  giteaRegistry?: string;
  /** Inner loop tag pattern (default: ^dev-[a-f0-9]{7}$) */
  innerLoopTagPattern?: string;
  /** Inner loop tags to ignore */
  innerLoopIgnoreTags?: string[];

  // Outer Loop Configuration
  /** Enable outer loop (GHCR → dev → staging → production) */
  enableOuterLoop?: boolean;
  /** GHCR registry URL (default: ghcr.io/pittampalliorg) */
  ghcrRegistry?: string;
  /** SemVer constraint for outer loop (default: >=1.0.0) */
  semverConstraint?: string;
  /** Outer loop tags to ignore */
  outerLoopIgnoreTags?: string[];

  // Stage Configuration
  /** Custom stage definitions (overrides default stages) */
  stages?: StageDefinition[];

  // ArgoCD Configuration
  /** ArgoCD namespace (default: 'argocd') */
  argocdNamespace?: string;
  /** Base repo URL for ArgoCD applications */
  repoUrl?: string;
}

/**
 * Default stage definitions for inner and outer loops
 */
const DEFAULT_INNER_LOOP_STAGES: StageDefinition[] = [
  {
    name: 'local-dev',
    isInnerLoop: true,
    directFromWarehouse: true,
    autoPromote: true,
  },
];

const DEFAULT_OUTER_LOOP_STAGES: StageDefinition[] = [
  {
    name: 'dev',
    isInnerLoop: false,
    directFromWarehouse: true,
    autoPromote: true,
  },
  {
    name: 'staging',
    isInnerLoop: false,
    directFromWarehouse: false,
    upstreamStage: 'dev',
    autoPromote: false,
  },
  {
    name: 'prod',
    isInnerLoop: false,
    directFromWarehouse: false,
    upstreamStage: 'staging',
    requiredSoakTime: '48h',
    autoPromote: false,
    isPlaceholder: true,
  },
];

/**
 * Kargo Pipeline Factory
 *
 * Creates complete Kargo pipelines for applications with:
 * - Inner Loop: Gitea → local-dev (rapid iteration)
 * - Outer Loop: GHCR → dev → staging → production (CI-verified)
 *
 * @example
 * ```typescript
 * // Create pipeline for a new application
 * const pipeline = KargoPipelineFactory.create(this, 'my-app-pipeline', {
 *   appName: 'my-app',
 *   enableInnerLoop: true,
 *   enableOuterLoop: true,
 * });
 * ```
 */
export class KargoPipelineFactory {
  /**
   * Create a complete Kargo pipeline for an application
   */
  static create(scope: Construct, id: string, config: PipelineConfig): void {
    const {
      appName,
      namespace = 'kargo-pipelines',
      enableInnerLoop = true,
      enableOuterLoop = true,
      giteaRegistry = REGISTRY.GITEA,
      ghcrRegistry = REGISTRY.GHCR,
      innerLoopTagPattern = TAG_PATTERNS.INNER_LOOP,
      innerLoopIgnoreTags = IGNORE_TAGS.INNER_LOOP,
      semverConstraint = '>=1.0.0',
      outerLoopIgnoreTags = IGNORE_TAGS.OUTER_LOOP,
      argocdNamespace = 'argocd',
      repoUrl = `cnoe://${appName}/manifests`,
    } = config;

    // Inner Loop
    if (enableInnerLoop) {
      const innerLoopStages = config.stages?.filter(s => s.isInnerLoop) ?? DEFAULT_INNER_LOOP_STAGES;

      // Create Gitea warehouse
      createWarehouse(scope, `${appName}-gitea-warehouse`, {
        name: `${appName}-gitea`,
        namespace,
        loopType: 'inner',
        syncWave: '20',
        subscriptions: [{
          repoUrl: `${giteaRegistry}/${appName}`,
          imageSelectionStrategy: WarehouseSpecSubscriptionsImageImageSelectionStrategy.LEXICAL,
          allowTags: innerLoopTagPattern,
          ignoreTags: innerLoopIgnoreTags,
          discoveryLimit: 10,
          insecureSkipTlsVerify: true,
          platform: 'linux/amd64',
        }],
      });

      // Create inner loop stages
      for (const stageDef of innerLoopStages) {
        const stageName = `${appName}-${stageDef.name}`;
        const argocdAppName = stageDef.argocdAppName ?? stageName;

        createStage(scope, `${stageName}-stage`, {
          name: stageName,
          namespace,
          warehouseName: `${appName}-gitea`,
          directFromWarehouse: stageDef.directFromWarehouse ?? true,
          upstreamStages: stageDef.upstreamStage ? [`${appName}-${stageDef.upstreamStage}`] : undefined,
          loopType: 'inner',
          syncWave: '30',
          argocdConfig: {
            appName: argocdAppName,
            namespace: argocdNamespace,
            repoUrl,
            imageRef: `${giteaRegistry}/${appName}`,
          },
          customVars: [
            { name: 'registry', value: giteaRegistry },
          ],
        });
      }
    }

    // Outer Loop
    if (enableOuterLoop) {
      const outerLoopStages = config.stages?.filter(s => !s.isInnerLoop) ?? DEFAULT_OUTER_LOOP_STAGES;

      // Create GHCR warehouse
      createWarehouse(scope, `${appName}-ghcr-warehouse`, {
        name: `${appName}-ghcr`,
        namespace,
        loopType: 'outer',
        syncWave: '20',
        subscriptions: [{
          repoUrl: `${ghcrRegistry}/${appName}`,
          imageSelectionStrategy: WarehouseSpecSubscriptionsImageImageSelectionStrategy.SEM_VER,
          semverConstraint,
          allowTags: TAG_PATTERNS.OUTER_LOOP_SEMVER,
          ignoreTags: outerLoopIgnoreTags,
          discoveryLimit: 30,
          insecureSkipTlsVerify: false,
          platform: 'linux/amd64',
          strictSemvers: true,
        }],
      });

      // Create outer loop stages
      for (const stageDef of outerLoopStages) {
        const stageName = `${appName}-${stageDef.name}`;
        const argocdAppName = stageDef.argocdAppName ?? stageName;

        createStage(scope, `${stageName}-stage`, {
          name: stageName,
          namespace,
          warehouseName: `${appName}-ghcr`,
          directFromWarehouse: stageDef.directFromWarehouse ?? false,
          upstreamStages: stageDef.upstreamStage ? [`${appName}-${stageDef.upstreamStage}`] : undefined,
          requiredSoakTime: stageDef.requiredSoakTime,
          loopType: 'outer',
          syncWave: '30',
          isPlaceholder: stageDef.isPlaceholder,
          argocdConfig: {
            appName: argocdAppName,
            namespace: argocdNamespace,
            repoUrl: stageDef.name === 'staging' || stageDef.name === 'prod'
              ? 'https://github.com/PittampalliOrg/stacks.git'
              : repoUrl,
            imageRef: `${ghcrRegistry}/${appName}`,
          },
          customVars: [
            { name: 'registry', value: ghcrRegistry },
          ],
        });
      }
    }
  }
}

/**
 * Props for KargoPipelineFactoryChart
 */
export interface KargoPipelineFactoryChartProps extends ChartProps, Omit<PipelineConfig, 'namespace'> {}

/**
 * CDK8s Chart wrapper for KargoPipelineFactory
 *
 * Use this chart in applications.ts to create pipelines declaratively.
 *
 * @example
 * ```typescript
 * // In applications.ts
 * {
 *   name: 'kargo-frontend-pipeline',
 *   namespace: 'kargo-pipelines',
 *   chart: {
 *     type: 'KargoPipelineFactoryChart',
 *     props: {
 *       appName: 'frontend',
 *       enableInnerLoop: true,
 *       enableOuterLoop: true,
 *     }
 *   }
 * }
 * ```
 */
export class KargoPipelineFactoryChart extends Chart {
  constructor(scope: Construct, id: string, props: KargoPipelineFactoryChartProps) {
    super(scope, id, props);

    KargoPipelineFactory.create(this, props.appName, props);
  }
}
