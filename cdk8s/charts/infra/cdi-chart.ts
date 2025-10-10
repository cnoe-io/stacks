/**
 * CDI (Containerized Data Importer) Chart
 *
 * Deploys CDI operator and custom resources for VM disk image imports.
 * CDI provides DataVolume CRD for importing VM images from HTTP, OCI registry, or PVC sources.
 *
 * Features:
 * - CDI namespace creation
 * - CDI CR for operator configuration
 * - Sync wave ordering for ArgoCD deployment
 *
 * User Story: US1 - Deploy KubeVirt to Kind Cluster (CDI is required for DataVolumes)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { Cdi } from '../../imports/cdi.kubevirt.io';

export interface CdiChartProps extends ChartProps {
  /**
   * CDI version to deploy
   * @default "v1.59.0"
   */
  version?: string;

  /**
   * Storage class for scratch space (temporary during import)
   * @default cluster default StorageClass
   */
  scratchSpaceStorageClass?: string;
}

export class CdiChart extends Chart {
  constructor(scope: Construct, id: string, props: CdiChartProps = {}) {
    super(scope, id, props);

    const { scratchSpaceStorageClass } = props;

    // Namespace for CDI operator and resources
    const namespace = new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: 'cdi',
        labels: {
          'app.kubernetes.io/name': 'cdi',
          'app.kubernetes.io/component': 'infrastructure',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-110',
        },
      },
    });

    // CDI CR (manages CDI deployment)
    // The CDI operator (deployed separately) watches this CR
    const cdi = new Cdi(this, 'cdi', {
      metadata: {
        name: 'cdi',
        namespace: 'cdi',
        labels: {
          'app.kubernetes.io/name': 'cdi',
          'app.kubernetes.io/component': 'operator',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      spec: {
        // Configuration for CDI features
        config: {
          // Scratch space storage class (for temporary import data)
          ...(scratchSpaceStorageClass
            ? { scratchSpaceStorageClass }
            : {}),
        },
      },
    });

    // Note: CDI operator deployment is installed via CRD import
    // The operator watches CDI CRs and manages component deployments:
    // - cdi-operator: Main operator
    // - cdi-apiserver: API server for DataVolume resources
    // - cdi-deployment: Controller for DataVolume reconciliation
    // - cdi-uploadproxy: Proxy for direct image uploads
    // - cdi-importer: Per-DataVolume import pods (ephemeral)
  }
}
