/**
 * CDI (Containerized Data Importer) Operator Chart
 *
 * Deploys the CDI operator to the cluster.
 * CDI provides DataVolume resources for importing VM disk images.
 *
 * This chart deploys the upstream CDI operator from the v1.62.0 release.
 */

import { Chart, ChartProps, Include, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';

export interface CDIOperatorChartProps extends ChartProps {
  /**
   * CDI version to deploy
   * @default "v1.62.0"
   */
  version?: string;
}

export class CDIOperatorChart extends Chart {
  constructor(scope: Construct, id: string, props: CDIOperatorChartProps = {}) {
    super(scope, id, props);

    const version = props.version || 'v1.62.0';

    // Deploy CDI operator from upstream release
    // This includes: operator deployment, RBAC, CRDs
    const include = new Include(this, 'cdi-operator', {
      url: `https://github.com/kubevirt/containerized-data-importer/releases/download/${version}/cdi-operator.yaml`,
    });

    // Kubernetes defaults `spec.conversion.strategy` to `None` on CRDs. Include it
    // explicitly to avoid perpetual ArgoCD OutOfSync drift.
    for (const apiObject of include.apiObjects) {
      if (apiObject.kind !== 'CustomResourceDefinition' || apiObject.name !== 'cdis.cdi.kubevirt.io') {
        continue;
      }

      apiObject.addJsonPatch(JsonPatch.add('/spec/conversion', { strategy: 'None' }));
      // CDI prunes the deprecated v1alpha1 from this CRD after install; match the
      // live shape so ArgoCD doesn't stay OutOfSync forever.
      apiObject.addJsonPatch(JsonPatch.remove('/spec/versions/0'));
    }
  }
}
