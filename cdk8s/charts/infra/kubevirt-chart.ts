/**
 * KubeVirt Chart
 *
 * Deploys KubeVirt operator and custom resources to Kubernetes cluster
 * for virtual machine management.
 *
 * Features:
 * - KubeVirt namespace creation
 * - KubeVirt CR with software emulation support (required for Kind)
 * - Sync wave ordering for ArgoCD deployment
 *
 * User Story: US1 - Deploy KubeVirt to Kind Cluster
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { KubeVirt } from '../../imports/kubevirt.io';

export interface KubeVirtChartProps extends ChartProps {
  /**
   * KubeVirt version to deploy
   * @default "v1.3.1"
   */
  version?: string;

  /**
   * Enable software emulation (QEMU without KVM)
   * Required for Kind cluster (no nested virtualization)
   * @default true
   */
  useEmulation?: boolean;

  /**
   * Additional feature gates to enable
   * @example ["LiveMigration", "CPUManager"]
   * @default []
   */
  featureGates?: string[];
}

export class KubeVirtChart extends Chart {
  constructor(scope: Construct, id: string, props: KubeVirtChartProps = {}) {
    super(scope, id, props);

    const {
      useEmulation = true, // Default true for Kind cluster
      featureGates = [],
    } = props;

    // Namespace for KubeVirt operator and resources
    const namespace = new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: 'kubevirt',
        labels: {
          'app.kubernetes.io/name': 'kubevirt',
          'app.kubernetes.io/component': 'infrastructure',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-110',
        },
      },
    });

    // KubeVirt CR (manages KubeVirt deployment)
    // The KubeVirt operator (deployed separately) watches this CR
    const kubevirt = new KubeVirt(this, 'kubevirt', {
      metadata: {
        name: 'kubevirt',
        namespace: 'kubevirt',
        labels: {
          'app.kubernetes.io/name': 'kubevirt',
          'app.kubernetes.io/component': 'operator',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      spec: {
        configuration: {
          developerConfiguration: {
            // Enable software emulation for Kind cluster (no KVM access)
            useEmulation,

            // Enable additional feature gates if specified
            ...(featureGates.length > 0 ? { featureGates } : {}),
          },
        },
        // Use default image pull policy
        imagePullPolicy: 'IfNotPresent',
      },
    });

    // Note: KubeVirt operator deployment is installed via CRD import
    // The operator watches KubeVirt CRs and manages component deployments:
    // - virt-operator: Main operator
    // - virt-controller: VM lifecycle management
    // - virt-handler: Node-level VM management (DaemonSet)
    // - virt-api: API server for KubeVirt resources
  }
}
