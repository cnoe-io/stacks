import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  createHubWarehouse,
  createSpokeTargetedStage,
  HUB_REGISTRY,
  HUB_TAG_PATTERNS,
  HUB_IGNORE_TAGS,
} from '../../lib/kargo-cross-cluster-helpers';
import { WarehouseSpecSubscriptionsImageImageSelectionStrategy } from '../../imports/kargo.akuity.io';
import { SpokeClusterName } from '../../lib/cluster-registry';

/**
 * Props for KargoHubBackstagePipelineChart
 */
export interface KargoHubBackstagePipelineChartProps extends ChartProps {
  /**
   * Enable inner loop pipeline (KIND Gitea → thinkpad spoke)
   * Hub Kargo watches KIND Gitea and promotes to KIND-targeted ArgoCD apps
   */
  enableInnerLoop?: boolean;
  /**
   * Enable outer loop pipeline (GHCR → dev → staging)
   * Hub Kargo watches GHCR and promotes through environments
   */
  enableOuterLoop?: boolean;
  /** KIND Gitea registry URL for inner loop */
  kindGiteaRegistry?: string;
  /** GHCR registry URL for outer loop */
  ghcrRegistry?: string;
  /** Inner loop target spoke (default: thinkpad) */
  innerLoopSpoke?: SpokeClusterName;
  /** Dev spoke cluster (default: thinkpad) */
  devSpoke?: SpokeClusterName;
  /** Staging spoke cluster (default: talos) */
  stagingSpoke?: SpokeClusterName;
  /** Git repository URL for manifests */
  gitRepoUrl?: string;
}

/**
 * Hub Kargo Backstage Pipeline Chart
 *
 * Creates cross-cluster pipelines for Backstage image promotion:
 *
 * INNER LOOP (rapid iteration ~60s):
 * - Warehouse: backstage-gitea (watches KIND Gitea registry)
 * - Stage: backstage-local-dev → ArgoCD App targeting thinkpad spoke
 *
 * OUTER LOOP (CI-verified ~5min):
 * - Warehouse: backstage-ghcr (watches GHCR for semver tags)
 * - Stage: backstage-dev (auto) → ArgoCD App targeting thinkpad spoke
 * - Stage: backstage-staging (manual) → ArgoCD App targeting talos spoke
 *
 * The hub ArgoCD manages applications that deploy to spoke clusters via
 * cluster secrets. Kargo runs only on hub and updates these applications.
 */
export class KargoHubBackstagePipelineChart extends Chart {
  constructor(scope: Construct, id: string, props: KargoHubBackstagePipelineChartProps = {}) {
    super(scope, id, props);

    const {
      enableInnerLoop = true,
      enableOuterLoop = true,
      kindGiteaRegistry = 'gitea.cnoe.localtest.me:8443/giteaadmin',
      ghcrRegistry = HUB_REGISTRY.GHCR,
      innerLoopSpoke = 'thinkpad',
      devSpoke = 'thinkpad',
      stagingSpoke = 'talos',
      gitRepoUrl = 'https://github.com/PittampalliOrg/stacks.git',
    } = props;

    const namespace = 'kargo-pipelines';
    const imageName = 'backstage-cnoe';

    // =========================================================================
    // Inner Loop: KIND Gitea → thinkpad spoke
    // Hub Kargo watches KIND's Gitea and promotes to KIND-targeted ArgoCD app
    // =========================================================================
    if (enableInnerLoop) {
      // Warehouse: backstage-gitea
      // Watches KIND Gitea OCI registry for dev-tagged images
      // NOTE: Hub needs network access to KIND Gitea via Tailscale
      createHubWarehouse(this, 'hub-backstage-gitea-warehouse', {
        name: 'hub-backstage-gitea',
        namespace,
        imageRepoUrl: `${kindGiteaRegistry}/${imageName}`,
        imageSelectionStrategy: WarehouseSpecSubscriptionsImageImageSelectionStrategy.LEXICAL,
        allowTags: HUB_TAG_PATTERNS.INNER_LOOP,
        ignoreTags: HUB_IGNORE_TAGS.INNER_LOOP,
        insecureSkipTlsVerify: true, // KIND Gitea uses self-signed certs
        interval: '1m0s', // Faster polling for inner loop
        syncWave: '20',
        loopType: 'inner',
      });

      // Stage: backstage-local-dev
      // Promotes from Gitea warehouse to KIND-targeted ArgoCD Application
      createSpokeTargetedStage(this, 'hub-backstage-local-dev-stage', {
        name: 'hub-backstage-local-dev',
        namespace,
        warehouseName: 'hub-backstage-gitea',
        targetSpoke: innerLoopSpoke,
        argocdAppName: 'backstage-local-dev',
        gitRepoUrl,
        imageRef: `${kindGiteaRegistry}/${imageName}`,
        directFromWarehouse: true,
        syncWave: '30',
        loopType: 'inner',
        simpleArgoCdUpdate: true, // Inner loop uses simple update (no git changes)
      });
    }

    // =========================================================================
    // Outer Loop: GHCR → dev (thinkpad) → staging (talos)
    // Hub Kargo watches GHCR and promotes through environments
    // =========================================================================
    if (enableOuterLoop) {
      // Warehouse: backstage-ghcr
      // Watches GHCR for CI-built semver-tagged images
      createHubWarehouse(this, 'hub-backstage-ghcr-warehouse', {
        name: 'hub-backstage-ghcr',
        namespace,
        imageRepoUrl: `${ghcrRegistry}/${imageName}`,
        imageSelectionStrategy: WarehouseSpecSubscriptionsImageImageSelectionStrategy.SEM_VER,
        semverConstraint: '>=1.0.0',
        allowTags: HUB_TAG_PATTERNS.OUTER_LOOP,
        ignoreTags: HUB_IGNORE_TAGS.OUTER_LOOP,
        insecureSkipTlsVerify: false, // GHCR has valid TLS
        interval: '5m0s',
        syncWave: '20',
        loopType: 'outer',
      });

      // Stage: backstage-dev
      // Auto-promotes from GHCR to dev environment on thinkpad spoke
      createSpokeTargetedStage(this, 'hub-backstage-dev-stage', {
        name: 'hub-backstage-dev',
        namespace,
        warehouseName: 'hub-backstage-ghcr',
        targetSpoke: devSpoke,
        argocdAppName: 'backstage-dev',
        gitRepoUrl,
        imageRef: `${ghcrRegistry}/${imageName}`,
        directFromWarehouse: true,
        syncWave: '30',
        loopType: 'outer',
        simpleArgoCdUpdate: true, // Dev stage uses simple update
      });

      // Stage: backstage-staging
      // Manual promotion from dev to staging environment on talos spoke
      createSpokeTargetedStage(this, 'hub-backstage-staging-stage', {
        name: 'hub-backstage-staging',
        namespace,
        warehouseName: 'hub-backstage-ghcr',
        targetSpoke: stagingSpoke,
        argocdAppName: 'backstage-staging',
        gitRepoUrl,
        imageRef: `${ghcrRegistry}/${imageName}`,
        directFromWarehouse: false,
        upstreamStages: ['hub-backstage-dev'],
        // Optional soak time requirement
        // requiredSoakTime: '24h',
        syncWave: '30',
        loopType: 'outer',
        simpleArgoCdUpdate: true, // Staging stage uses simple update
      });
    }
  }
}
