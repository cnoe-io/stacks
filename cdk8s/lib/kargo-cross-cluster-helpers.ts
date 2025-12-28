import { Construct } from 'constructs';
import {
  Stage,
  Warehouse,
  WarehouseSpecSubscriptionsImageImageSelectionStrategy,
  WarehouseSpecFreightCreationPolicy,
  StageSpecRequestedFreightOriginKind,
} from '../imports/kargo.akuity.io';
import { SpokeClusterName, getSpokeCluster } from './cluster-registry';

/**
 * Cross-cluster Kargo helpers for hub-and-spoke architecture.
 *
 * In the hub-spoke model:
 * - Kargo runs only on the hub cluster
 * - Hub ArgoCD manages applications that target spoke clusters
 * - Kargo stages update ArgoCD Applications on hub
 * - ArgoCD then deploys to spokes via cluster secrets
 *
 * Flow: Warehouse → Stage (hub) → ArgoCD App (hub) → Deploy to Spoke
 */

/**
 * Configuration for cross-cluster warehouse
 */
export interface CrossClusterWarehouseConfig {
  /** Warehouse name */
  name: string;
  /** Namespace (typically 'kargo-pipelines') */
  namespace: string;
  /** Image repository URL */
  imageRepoUrl: string;
  /** Image selection strategy */
  imageSelectionStrategy?: WarehouseSpecSubscriptionsImageImageSelectionStrategy;
  /** SemVer constraint (for SemVer strategy) */
  semverConstraint?: string;
  /** Tag pattern to allow */
  allowTags?: string;
  /** Tags to ignore */
  ignoreTags?: string[];
  /** Skip TLS verification (for self-signed certs) */
  insecureSkipTlsVerify?: boolean;
  /** Polling interval (default: '5m0s') */
  interval?: string;
  /** Sync wave for ArgoCD ordering */
  syncWave?: string;
  /** Loop type for labeling */
  loopType?: 'inner' | 'outer';
}

/**
 * Creates a Kargo Warehouse on hub cluster for watching OCI registries
 */
export function createHubWarehouse(
  scope: Construct,
  id: string,
  config: CrossClusterWarehouseConfig
): Warehouse {
  return new Warehouse(scope, id, {
    metadata: {
      name: config.name,
      namespace: config.namespace,
      annotations: {
        'argocd.argoproj.io/sync-wave': config.syncWave ?? '20',
      },
      labels: {
        'app.kubernetes.io/name': `${config.name}-warehouse`,
        'app.kubernetes.io/part-of': 'hub-kargo-pipelines',
        'app.kubernetes.io/component': 'warehouse',
        'kargo.akuity.io/loop': config.loopType ?? 'outer',
        'kargo.akuity.io/cluster': 'hub',
      },
    },
    spec: {
      freightCreationPolicy: WarehouseSpecFreightCreationPolicy.AUTOMATIC,
      interval: config.interval ?? '5m0s',
      subscriptions: [
        {
          image: {
            repoUrl: config.imageRepoUrl,
            imageSelectionStrategy: config.imageSelectionStrategy,
            semverConstraint: config.semverConstraint,
            allowTags: config.allowTags,
            ignoreTags: config.ignoreTags,
            discoveryLimit: 20,
            insecureSkipTlsVerify: config.insecureSkipTlsVerify ?? false,
            platform: 'linux/amd64',
            strictSemvers: true,
          },
        },
      ],
    },
  });
}

/**
 * Configuration for spoke-targeted stage
 */
export interface SpokeTargetedStageConfig {
  /** Stage name */
  name: string;
  /** Namespace (typically 'kargo-pipelines') */
  namespace: string;
  /** Source warehouse name */
  warehouseName: string;
  /** Target spoke cluster */
  targetSpoke: SpokeClusterName;
  /** ArgoCD Application name (on hub, targets spoke) */
  argocdAppName: string;
  /** Git repository URL for manifests */
  gitRepoUrl: string;
  /** Image reference for updates */
  imageRef: string;
  /** Get freight directly from warehouse */
  directFromWarehouse?: boolean;
  /** Upstream stage names (when not direct) */
  upstreamStages?: string[];
  /** Required soak time in upstream */
  requiredSoakTime?: string;
  /** Sync wave for ArgoCD ordering */
  syncWave?: string;
  /** Loop type for labeling */
  loopType?: 'inner' | 'outer';
  /** Use simple argocd-update (no git changes) */
  simpleArgoCdUpdate?: boolean;
}

/**
 * Creates a Kargo Stage on hub that promotes to spoke-targeted ArgoCD Application.
 *
 * The stage runs on hub cluster and updates an ArgoCD Application that has
 * destination.name set to a spoke cluster (e.g., 'thinkpad', 'hetzner').
 */
export function createSpokeTargetedStage(
  scope: Construct,
  id: string,
  config: SpokeTargetedStageConfig
): Stage {
  const spokeCluster = getSpokeCluster(config.targetSpoke);

  const labels: Record<string, string> = {
    'app.kubernetes.io/name': `${config.name}-stage`,
    'app.kubernetes.io/part-of': 'hub-kargo-pipelines',
    'app.kubernetes.io/component': 'stage',
    'kargo.akuity.io/loop': config.loopType ?? 'outer',
    'kargo.akuity.io/cluster': 'hub',
    'kargo.akuity.io/target-spoke': config.targetSpoke,
    'kargo.akuity.io/target-environment': spokeCluster.environment,
  };

  const annotations: Record<string, string> = {
    'argocd.argoproj.io/sync-wave': config.syncWave ?? '30',
  };

  // Build requested freight source
  const sources: {
    direct?: boolean;
    stages?: string[];
    requiredSoakTime?: string;
  } = {};

  if (config.directFromWarehouse) {
    sources.direct = true;
  } else if (config.upstreamStages && config.upstreamStages.length > 0) {
    sources.stages = config.upstreamStages;
    if (config.requiredSoakTime) {
      sources.requiredSoakTime = config.requiredSoakTime;
    }
  }

  // Build promotion template variables
  const vars = [
    { name: 'appName', value: config.argocdAppName },
    { name: 'argocdNamespace', value: 'argocd' },
    { name: 'repoUrl', value: config.gitRepoUrl },
    { name: 'imageRef', value: config.imageRef },
    { name: 'targetSpoke', value: config.targetSpoke },
    { name: 'targetEnvironment', value: spokeCluster.environment },
  ];

  // Build promotion steps
  // For hub-spoke, we update the ArgoCD App on hub which targets the spoke
  const steps = config.simpleArgoCdUpdate
    ? [
        // Simple mode: just trigger ArgoCD sync
        {
          uses: 'argocd-update',
          as: 'sync-argocd-app',
          config: {
            apps: [
              {
                name: config.argocdAppName,
                namespace: 'argocd',
              },
            ],
          },
        },
      ]
    : [
        // Full GitOps mode for hub-managed repos
        {
          uses: 'git-clone',
          as: 'clone-repo',
          config: {
            repoURL: config.gitRepoUrl,
            checkout: [
              {
                path: './repo',
                branch: 'main',
              },
            ],
          },
        },
        {
          uses: 'kustomize-set-image',
          as: 'update-image',
          config: {
            path: './repo',
            images: [
              {
                image: config.imageRef,
                tag: '${{ imageFrom("' + config.imageRef + '").Tag }}',
              },
            ],
          },
        },
        {
          uses: 'git-commit',
          as: 'commit-changes',
          config: {
            path: './repo',
            message: `chore(${config.targetSpoke}): update ${config.imageRef} to $\{{ imageFrom("${config.imageRef}").Tag }}`,
          },
        },
        {
          uses: 'git-push',
          as: 'push-changes',
          config: {
            path: './repo',
          },
        },
        {
          uses: 'argocd-update',
          as: 'sync-argocd-app',
          config: {
            apps: [
              {
                name: config.argocdAppName,
                namespace: 'argocd',
                sources: [
                  {
                    repoURL: config.gitRepoUrl,
                    desiredRevision: "${{ outputs['push-changes'].commit }}",
                  },
                ],
              },
            ],
          },
        },
      ];

  return new Stage(scope, id, {
    metadata: {
      name: config.name,
      namespace: config.namespace,
      annotations,
      labels,
    },
    spec: {
      requestedFreight: [
        {
          origin: {
            kind: StageSpecRequestedFreightOriginKind.WAREHOUSE,
            name: config.warehouseName,
          },
          sources,
        },
      ],
      promotionTemplate: {
        spec: {
          vars,
          steps,
        },
      },
    },
  });
}

/**
 * Hub registry URLs for cross-cluster pipelines
 */
export const HUB_REGISTRY = {
  /** GHCR for outer loop production builds (pittampalliorg/backstage-cnoe) */
  GHCR: 'ghcr.io/pittampalliorg',
  /** GitHub Container Registry base */
  GITHUB: 'ghcr.io',
};

/**
 * Inner loop configuration for KIND spoke
 * Hub Kargo watches KIND Gitea and promotes to KIND spoke
 */
export interface InnerLoopConfig {
  /** Application name */
  appName: string;
  /** KIND Gitea registry URL */
  giteaRegistryUrl: string;
  /** Image name */
  imageName: string;
  /** ArgoCD Application name on hub targeting KIND */
  kindArgocdAppName: string;
  /** Git repository URL */
  gitRepoUrl: string;
}

/**
 * Outer loop configuration for production spokes
 * Hub Kargo watches GHCR and promotes through staging to production
 */
export interface OuterLoopConfig {
  /** Application name */
  appName: string;
  /** GHCR image URL */
  ghcrImageUrl: string;
  /** Dev stage ArgoCD App (targets KIND) */
  devArgocdAppName: string;
  /** Staging stage ArgoCD App (targets staging spoke) */
  stagingArgocdAppName: string;
  /** Production stage ArgoCD App (targets production spoke) */
  prodArgocdAppName?: string;
  /** Git repository URL */
  gitRepoUrl: string;
  /** Staging spoke cluster */
  stagingSpoke: SpokeClusterName;
  /** Production spoke cluster */
  prodSpoke?: SpokeClusterName;
}

/**
 * Tag patterns for hub pipelines
 */
export const HUB_TAG_PATTERNS = {
  /** Inner loop: dev-YYYYMMDD-HHMMSS pattern */
  INNER_LOOP: '^dev-[0-9]{8}-[0-9]{6}(-[a-f0-9]{7})?$',
  /** Outer loop: semver pattern */
  OUTER_LOOP: '^v?\\d+\\.\\d+\\.\\d+$',
};

/**
 * Common tags to ignore
 */
export const HUB_IGNORE_TAGS = {
  INNER_LOOP: ['latest', 'main', 'develop'],
  OUTER_LOOP: ['latest', 'main', 'develop', 'nightly'],
};
