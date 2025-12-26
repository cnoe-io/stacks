import { Construct } from 'constructs';
import {
  Warehouse,
  Stage,
  WarehouseSpecSubscriptionsImageImageSelectionStrategy,
  WarehouseSpecFreightCreationPolicy,
  StageSpecRequestedFreightOriginKind,
} from '../imports/kargo.akuity.io';

/**
 * Configuration for image warehouse subscriptions
 */
export interface ImageSubscriptionConfig {
  /** Image repository URL (without tag) */
  repoUrl: string;
  /** Image selection strategy (SemVer, Lexical, Digest, NewestBuild) */
  imageSelectionStrategy?: WarehouseSpecSubscriptionsImageImageSelectionStrategy;
  /** SemVer constraint (e.g., '>=1.0.0') - only for SemVer strategy */
  semverConstraint?: string;
  /** Regex pattern to whitelist tags */
  allowTags?: string;
  /** Tags to ignore (exact match) */
  ignoreTags?: string[];
  /** Max images to examine (default: 20, max: 100) */
  discoveryLimit?: number;
  /** Skip TLS verification (for self-signed certs like Gitea) */
  insecureSkipTlsVerify?: boolean;
  /** Target platform (e.g., 'linux/amd64') */
  platform?: string;
  /** Require strict semver (major.minor.patch) - only for SemVer strategy */
  strictSemvers?: boolean;
}

/**
 * Configuration for creating a Kargo Warehouse
 */
export interface WarehouseConfig {
  /** Warehouse name */
  name: string;
  /** Namespace (typically 'kargo-pipelines') */
  namespace: string;
  /** Image subscriptions */
  subscriptions: ImageSubscriptionConfig[];
  /** Sync wave for ArgoCD ordering */
  syncWave?: string;
  /** Loop type for labeling (inner or outer) */
  loopType?: 'inner' | 'outer';
  /** Polling interval (e.g., '5m0s') */
  interval?: string;
}

/**
 * Creates a Kargo Warehouse for monitoring OCI registries
 */
export function createWarehouse(scope: Construct, id: string, config: WarehouseConfig): Warehouse {
  return new Warehouse(scope, id, {
    metadata: {
      name: config.name,
      namespace: config.namespace,
      annotations: {
        'argocd.argoproj.io/sync-wave': config.syncWave ?? '20',
      },
      labels: {
        'app.kubernetes.io/name': `${config.name}-warehouse`,
        'app.kubernetes.io/part-of': 'kargo-pipelines',
        'app.kubernetes.io/component': 'warehouse',
        'kargo.akuity.io/loop': config.loopType ?? 'outer',
      },
    },
    spec: {
      freightCreationPolicy: WarehouseSpecFreightCreationPolicy.AUTOMATIC,
      interval: config.interval ?? '5m0s',
      subscriptions: config.subscriptions.map(sub => ({
        image: {
          repoUrl: sub.repoUrl,
          imageSelectionStrategy: sub.imageSelectionStrategy,
          semverConstraint: sub.semverConstraint,
          allowTags: sub.allowTags,
          ignoreTags: sub.ignoreTags,
          discoveryLimit: sub.discoveryLimit ?? 20,
          insecureSkipTlsVerify: sub.insecureSkipTlsVerify ?? false,
          platform: sub.platform ?? 'linux/amd64',
          strictSemvers: sub.strictSemvers ?? true,
        },
      })),
    },
  });
}

/**
 * Configuration for ArgoCD update step in promotion template
 */
export interface ArgoCdUpdateConfig {
  /** ArgoCD Application name */
  appName: string;
  /** ArgoCD namespace (default: 'argocd') */
  namespace?: string;
  /** Source repository URL (Git repo that ArgoCD watches) */
  repoUrl: string;
  /** Image reference to update */
  imageRef: string;
  /** Git credentials secret name (for pushing changes) */
  gitCredentialsSecret?: string;
}

/**
 * Configuration for creating a Kargo Stage
 */
export interface StageConfig {
  /** Stage name */
  name: string;
  /** Namespace (typically 'kargo-pipelines') */
  namespace: string;
  /** Source warehouse name */
  warehouseName: string;
  /** Get freight directly from warehouse (true) or from upstream stages (false) */
  directFromWarehouse?: boolean;
  /** Upstream stage names (when directFromWarehouse is false) */
  upstreamStages?: string[];
  /** Required soak time in upstream stage (e.g., '24h') */
  requiredSoakTime?: string;
  /** ArgoCD update configuration */
  argocdConfig: ArgoCdUpdateConfig;
  /** Sync wave for ArgoCD ordering */
  syncWave?: string;
  /** Loop type for labeling (inner or outer) */
  loopType?: 'inner' | 'outer';
  /** Custom variables for promotion template */
  customVars?: { name: string; value: string }[];
  /** Mark as placeholder (for future stages) */
  isPlaceholder?: boolean;
  /** Use simple argocd-update (no git changes) - for apps that don't need image updates in git */
  simpleArgoCdUpdate?: boolean;
}

/**
 * Creates a Kargo Stage for deployment targets
 */
export function createStage(scope: Construct, id: string, config: StageConfig): Stage {
  const labels: Record<string, string> = {
    'app.kubernetes.io/name': `${config.name}-stage`,
    'app.kubernetes.io/part-of': 'kargo-pipelines',
    'app.kubernetes.io/component': 'stage',
    'kargo.akuity.io/loop': config.loopType ?? 'outer',
  };

  const annotations: Record<string, string> = {
    'argocd.argoproj.io/sync-wave': config.syncWave ?? '30',
  };

  if (config.isPlaceholder) {
    annotations['kargo.akuity.io/placeholder'] = 'true';
  }

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
  const defaultVars = [
    { name: 'appName', value: config.argocdConfig.appName },
    { name: 'argocdNamespace', value: config.argocdConfig.namespace ?? 'argocd' },
    { name: 'repoUrl', value: config.argocdConfig.repoUrl },
    { name: 'imageRef', value: config.argocdConfig.imageRef },
  ];

  const vars = [...defaultVars, ...(config.customVars ?? [])];

  // Build promotion steps based on configuration
  // For Git-based ArgoCD apps, we need to: clone -> update image -> commit -> push -> sync
  const steps = config.simpleArgoCdUpdate
    ? [
        // Simple mode: just trigger ArgoCD sync (for apps that manage images differently)
        {
          uses: 'argocd-update',
          as: 'sync-argocd-app',
          config: {
            apps: [
              {
                name: config.argocdConfig.appName,
                namespace: config.argocdConfig.namespace ?? 'argocd',
              },
            ],
          },
        },
      ]
    : [
        // Full GitOps mode: clone, update image in manifests, commit, push, then sync
        {
          uses: 'git-clone',
          as: 'clone-repo',
          config: {
            repoURL: config.argocdConfig.repoUrl,
            checkout: [
              {
                path: './repo',
                branch: 'main',
              },
            ],
            insecureSkipTLSVerify: true, // For self-signed Gitea certs
          },
        },
        {
          uses: 'kustomize-set-image',
          as: 'update-image',
          config: {
            path: './repo',
            images: [
              {
                image: config.argocdConfig.imageRef,
                tag: '${{ imageFrom("' + config.argocdConfig.imageRef + '").Tag }}',
              },
            ],
          },
        },
        {
          uses: 'git-commit',
          as: 'commit-changes',
          config: {
            path: './repo',
            message: "${{ outputs['update-image'].commitMessage }}",
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
                name: config.argocdConfig.appName,
                namespace: config.argocdConfig.namespace ?? 'argocd',
                sources: [
                  {
                    repoURL: config.argocdConfig.repoUrl,
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
 * Gitea host configuration
 *
 * GITEA can be configured via environment variables:
 * - GITEA_TAILSCALE_HOST: Tailscale hostname for Gitea (e.g., 'gitea-thinkpad.tail286401.ts.net')
 *   When set, uses Tailscale address which is accessible from cluster worker nodes.
 * - Falls back to 'gitea.cnoe.localtest.me:8443' (only works in single-node clusters)
 */
const giteaTailscaleHost = process.env.GITEA_TAILSCALE_HOST;
const giteaHost = giteaTailscaleHost || 'gitea.cnoe.localtest.me:8443';
const giteaRegistry = `${giteaHost}/giteaadmin`;

/**
 * Gitea host URLs for Git and registry operations
 */
export const GITEA = {
  /** Current Gitea host (Tailscale if set, otherwise local) */
  HOST: giteaHost,
  /** Tailscale host if configured, null otherwise */
  TAILSCALE_HOST: giteaTailscaleHost || null,
  /** Local Gitea host (always available, but may not work from worker nodes) */
  LOCAL_HOST: 'gitea.cnoe.localtest.me:8443',
  /** Git base URL for Gitea repositories */
  GIT_BASE_URL: `https://${giteaHost}/giteaAdmin`,
  /** Local Git base URL */
  GIT_BASE_URL_LOCAL: 'https://gitea.cnoe.localtest.me:8443/giteaAdmin',
  /** Whether we're using Tailscale */
  IS_TAILSCALE: !!giteaTailscaleHost,
};

/**
 * Default registry URLs
 */
export const REGISTRY = {
  GITEA: giteaRegistry,
  GITEA_LOCAL: 'gitea.cnoe.localtest.me:8443/giteaadmin',
  GITEA_TAILSCALE: giteaTailscaleHost ? `${giteaTailscaleHost}/giteaadmin` : null,
  GHCR: 'ghcr.io/vpittamp',
};

/**
 * Default image tag patterns
 */
export const TAG_PATTERNS = {
  /** Inner loop dev builds: dev-YYYYMMDD-HHMMSS[-<sha7>] */
  INNER_LOOP: '^dev-[0-9]{8}-[0-9]{6}(-[a-f0-9]{7})?$',
  /** Outer loop semver: v1.2.3 or 1.2.3 */
  OUTER_LOOP_SEMVER: '^v?\\d+\\.\\d+\\.\\d+$',
};

/**
 * Common tags to ignore
 */
export const IGNORE_TAGS = {
  INNER_LOOP: ['latest', 'develop', 'main'],
  OUTER_LOOP: ['latest', 'main', 'develop', 'nightly'],
};
