/**
 * DaprTracingConfigChart - Dapr Tracing Configuration
 *
 * Creates a Dapr Configuration CRD that configures tracing for SpecKit agents.
 * - Zipkin protocol to Jaeger collector
 * - 100% sampling rate for development
 *
 * Sync wave: -55 (after Jaeger is deployed at -65)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { ApiObject } from 'cdk8s';

export interface DaprTracingConfigChartProps extends ChartProps {
  /**
   * Namespace for the Dapr Configuration
   * @default 'dapr-agents'
   */
  namespace?: string;

  /**
   * Configuration name
   * @default 'speckit-tracing'
   */
  configName?: string;

  /**
   * Sampling rate (0.0 to 1.0, where "1" = 100%)
   * @default '1'
   */
  samplingRate?: string;

  /**
   * Jaeger collector endpoint (Zipkin format)
   * @default 'http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans'
   */
  zipkinEndpoint?: string;
}

export class DaprTracingConfigChart extends Chart {
  constructor(scope: Construct, id: string, props?: DaprTracingConfigChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'dapr-agents';
    const configName = props?.configName || 'speckit-tracing';
    const samplingRate = props?.samplingRate || '1';
    const zipkinEndpoint = props?.zipkinEndpoint ||
      'http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans';

    // Dapr Configuration CRD for tracing
    new ApiObject(this, 'tracing-config', {
      apiVersion: 'dapr.io/v1alpha1',
      kind: 'Configuration',
      metadata: {
        name: configName,
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': configName,
          'app.kubernetes.io/component': 'tracing',
          'app.kubernetes.io/part-of': 'speckit-agents',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-55',
        },
      },
      spec: {
        tracing: {
          samplingRate: samplingRate,
          zipkin: {
            endpointAddress: zipkinEndpoint,
          },
        },
      },
    });
  }
}
