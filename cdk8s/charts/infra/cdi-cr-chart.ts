/**
 * CDI Custom Resource Chart
 *
 * Creates the CDI custom resource that configures the CDI platform.
 * This must be deployed AFTER the CDI operator (sync wave -90 vs -100).
 */

import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

export interface CDICRChartProps extends ChartProps {}

export class CDICRChart extends Chart {
  constructor(scope: Construct, id: string, props: CDICRChartProps = {}) {
    super(scope, id, props);

    // Create CDI CR with default configuration
    new ApiObject(this, 'cdi', {
      apiVersion: 'cdi.kubevirt.io/v1beta1',
      kind: 'CDI',
      metadata: {
        name: 'cdi',
        namespace: 'cdi',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      spec: {
        imagePullPolicy: 'IfNotPresent',
      },
    });
  }
}
