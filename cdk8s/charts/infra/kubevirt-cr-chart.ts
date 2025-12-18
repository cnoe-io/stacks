/**
 * KubeVirt Custom Resource Chart
 *
 * Creates the KubeVirt custom resource that configures the KubeVirt platform.
 * This must be deployed AFTER the KubeVirt operator (sync wave -90 vs -100).
 *
 * For Kind clusters, useEmulation MUST be enabled (no KVM access).
 */

import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

export interface KubeVirtCRChartProps extends ChartProps {
  /**
   * Enable software emulation (required for Kind)
   * @default true
   */
  useEmulation?: boolean;

  /**
   * Additional feature gates to enable
   * @default []
   */
  featureGates?: string[];
}

export class KubeVirtCRChart extends Chart {
  constructor(scope: Construct, id: string, props: KubeVirtCRChartProps = {}) {
    super(scope, id, props);

    const useEmulation = props.useEmulation ?? true;
    const featureGates = props.featureGates || [];

    // Create KubeVirt CR with software emulation for Kind
    new ApiObject(this, 'kubevirt', {
      apiVersion: 'kubevirt.io/v1',
      kind: 'KubeVirt',
      metadata: {
        name: 'kubevirt',
        namespace: 'kubevirt',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      spec: {
        configuration: {
          developerConfiguration: {
            useEmulation,
            ...(featureGates.length > 0 ? { featureGates } : {}),
          },
        },
        imagePullPolicy: 'IfNotPresent',
      },
    });
  }
}
