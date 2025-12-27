import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  createWarehouse,
  createStage,
  REGISTRY,
  GITEA,
  TAG_PATTERNS,
  IGNORE_TAGS,
} from '../../lib/kargo-helpers';
import { WarehouseSpecSubscriptionsImageImageSelectionStrategy } from '../../imports/kargo.akuity.io';

/**
 * Props for KargoBackstagePipelineChart
 */
export interface KargoBackstagePipelineChartProps extends ChartProps {
  /** Enable inner loop pipeline (Gitea → local-dev) */
  enableInnerLoop?: boolean;
  /** Enable outer loop pipeline (GHCR → dev) */
  enableOuterLoop?: boolean;
  /** Optionally include staging/prod placeholder stages */
  enableStagingAndProdStages?: boolean;
  /** Gitea registry URL (default: gitea.cnoe.localtest.me:8443/giteaadmin) */
  giteaRegistry?: string;
  /** GHCR registry URL (default: ghcr.io/pittampalliorg) */
  ghcrRegistry?: string;
}

/**
 * Kargo Backstage Pipeline Chart
 *
 * Creates parallel pipelines for Backstage image promotion:
 * - Inner Loop: Gitea → local-dev (rapid iteration, auto-promote)
 * - Outer Loop: GHCR → dev → staging → production (CI-verified, manual for staging+)
 */
export class KargoBackstagePipelineChart extends Chart {
  constructor(scope: Construct, id: string, props: KargoBackstagePipelineChartProps = {}) {
    super(scope, id, props);

    const {
      enableInnerLoop = true,
      enableOuterLoop = true,
      enableStagingAndProdStages = false,
      giteaRegistry = REGISTRY.GITEA,
      ghcrRegistry = REGISTRY.GHCR,
    } = props;

    const namespace = 'kargo-pipelines';
    const appName = 'backstage';
    // Local (Gitea) image is published as 'backstage-cnoe' (different from app name)
    const giteaImageName = 'backstage-cnoe';
    // GHCR image is now published as 'backstage-app' (vpittamp repo)
    const ghcrImageName = 'backstage-app';
    const clusterHost = process.env.CLUSTER_HOST || 'localdev';

    // =========================================================================
    // Inner Loop: Gitea → local-dev
    // Purpose: Rapid sub-minute iteration for local development
    // =========================================================================
    if (enableInnerLoop) {
      // Warehouse: backstage-gitea
      // Monitors Gitea OCI registry for locally-pushed dev images
      createWarehouse(this, 'backstage-gitea-warehouse', {
        name: 'backstage-gitea',
        namespace,
        loopType: 'inner',
        syncWave: '20',
        interval: '5m0s',
        subscriptions: [
          {
            repoUrl: `${giteaRegistry}/${giteaImageName}`,
            imageSelectionStrategy: WarehouseSpecSubscriptionsImageImageSelectionStrategy.LEXICAL,
            allowTags: TAG_PATTERNS.INNER_LOOP,
            ignoreTags: IGNORE_TAGS.INNER_LOOP,
            discoveryLimit: 10,
            insecureSkipTlsVerify: true, // Gitea uses self-signed certificates
            platform: 'linux/amd64',
          },
        ],
      });

      // Stage: backstage-local-dev
      // Auto-promotes new images from Gitea warehouse to local-dev deployment
      // Uses GITEA.GIT_BASE_URL which respects GITEA_TAILSCALE_HOST env var
      createStage(this, 'backstage-local-dev-stage', {
        name: 'backstage-local-dev',
        namespace,
        warehouseName: 'backstage-gitea',
        directFromWarehouse: true,
        loopType: 'inner',
        syncWave: '30',
        argocdConfig: {
          appName: 'backstage-local-dev',
          namespace: 'argocd',
          repoUrl: `${GITEA.GIT_BASE_URL}/idpbuilder-${clusterHost}-backstage-local-dev-manifests.git`,
          imageRef: `${giteaRegistry}/${giteaImageName}`,
        },
        customVars: [
          { name: 'registry', value: giteaRegistry },
        ],
      });
    }

    // =========================================================================
    // Outer Loop: GHCR → dev → staging → production
    // Purpose: CI-verified images flowing through environments
    // =========================================================================
    if (enableOuterLoop) {
      // Warehouse: backstage-ghcr
      // Monitors GHCR for CI-built semver-tagged images
      createWarehouse(this, 'backstage-ghcr-warehouse', {
        name: 'backstage-ghcr',
        namespace,
        loopType: 'outer',
        syncWave: '20',
        interval: '5m0s',
        subscriptions: [
          {
            repoUrl: `${ghcrRegistry}/${ghcrImageName}`,
            imageSelectionStrategy: WarehouseSpecSubscriptionsImageImageSelectionStrategy.SEM_VER,
            semverConstraint: '>=0.1.0',
            allowTags: TAG_PATTERNS.OUTER_LOOP_SEMVER,
            ignoreTags: IGNORE_TAGS.OUTER_LOOP,
            discoveryLimit: 30,
            insecureSkipTlsVerify: false, // GHCR has valid TLS
            platform: 'linux/amd64',
            strictSemvers: true,
          },
        ],
      });

      // Stage: backstage (primary)
      // Auto-promotes new CI images to primary backstage deployment
      // Note: Using actual Gitea URL for git operations (idpbuilder translates cnoe:// URLs)
      const giteaBaseUrl = 'https://gitea.cnoe.localtest.me:8443/giteaAdmin';
      createStage(this, 'backstage-stage', {
        name: 'backstage',
        namespace,
        warehouseName: 'backstage-ghcr',
        directFromWarehouse: true,
        loopType: 'outer',
        syncWave: '30',
        argocdConfig: {
          appName: 'backstage',
          namespace: 'argocd',
          repoUrl: `${giteaBaseUrl}/idpbuilder-${clusterHost}-backstage-manifests.git`,
          imageRef: `${ghcrRegistry}/${ghcrImageName}`,
        },
        customVars: [
          { name: 'registry', value: ghcrRegistry },
        ],
      });

      if (enableStagingAndProdStages) {
        // Stage: backstage-staging
        // Manual promotion from primary backstage to staging (Talos cluster)
        createStage(this, 'backstage-staging-stage', {
          name: 'backstage-staging',
          namespace,
          warehouseName: 'backstage-ghcr',
          directFromWarehouse: false,
          upstreamStages: ['backstage'],
          // Optional: requiredSoakTime: '24h',
          loopType: 'outer',
          syncWave: '30',
          argocdConfig: {
            appName: 'backstage-staging',
            namespace: 'argocd',
            // Git repo for staging-specific manifests
            repoUrl: 'https://github.com/PittampalliOrg/stacks.git',
            imageRef: `${ghcrRegistry}/${ghcrImageName}`,
          },
          customVars: [
            { name: 'registry', value: ghcrRegistry },
            { name: 'clusterUrl', value: 'https://talos-cluster.example.com:6443' },
          ],
        });

        // Stage: backstage-prod (Placeholder)
        // Manual promotion from staging with 48h soak time
        createStage(this, 'backstage-prod-stage', {
          name: 'backstage-prod',
          namespace,
          warehouseName: 'backstage-ghcr',
          directFromWarehouse: false,
          upstreamStages: ['backstage-staging'],
          requiredSoakTime: '48h',
          loopType: 'outer',
          syncWave: '30',
          isPlaceholder: true, // Mark as placeholder until production cluster is available
          argocdConfig: {
            appName: 'backstage-prod',
            namespace: 'argocd',
            repoUrl: 'https://github.com/PittampalliOrg/stacks.git',
            imageRef: `${ghcrRegistry}/${ghcrImageName}`,
          },
          customVars: [
            { name: 'registry', value: ghcrRegistry },
            { name: 'clusterUrl', value: 'https://production-cluster.example.com:6443' },
          ],
        });
      }
    }
  }
}
