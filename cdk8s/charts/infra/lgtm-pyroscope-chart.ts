/**
 * LgtmPyroscopeChart - Grafana Pyroscope Deployment for Continuous Profiling
 *
 * Deploys Pyroscope standalone instance with filesystem storage.
 * Provides continuous profiling with flame graph visualization.
 *
 * Feature: 111-configure-k8s-observability
 * Sync wave: -60 (after namespace)
 *
 * Ports:
 * - 4040: HTTP API (push, query)
 *
 * Endpoints:
 * - Push/Query: http://pyroscope:4040
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  LGTM_NAMESPACE,
  LGTM_IMAGES,
  LGTM_STORAGE,
  LGTM_RESOURCES,
  getLgtmComponentLabels,
  getLgtmSelectorLabels,
  toK8sResources,
} from '../../lib/lgtm-helpers';

export interface LgtmPyroscopeChartProps extends ChartProps {
  /**
   * Namespace for Pyroscope deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Storage size for Pyroscope profile data
   * @default '10Gi'
   */
  storageSize?: string;

  /**
   * Pyroscope container image
   * @default 'grafana/pyroscope:1.10.0'
   */
  image?: string;

  /**
   * Resource requests and limits
   */
  resources?: {
    requests?: { cpu?: string; memory?: string };
    limits?: { cpu?: string; memory?: string };
  };
}

export class LgtmPyroscopeChart extends Chart {
  constructor(scope: Construct, id: string, props?: LgtmPyroscopeChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || LGTM_NAMESPACE;
    const storageSize = props?.storageSize || LGTM_STORAGE.pyroscope;
    const image = props?.image || LGTM_IMAGES.pyroscope;
    const resources = props?.resources || LGTM_RESOURCES.pyroscope;

    const labels = getLgtmComponentLabels('pyroscope', 'profiles-backend');
    const selectorLabels = getLgtmSelectorLabels('pyroscope');

    // PersistentVolumeClaim for Pyroscope data
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'pyroscope-data',
        namespace,
        labels,
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString(storageSize),
          },
        },
      },
    });

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'pyroscope',
        namespace,
        labels,
      },
      spec: {
        replicas: 1,
        strategy: { type: 'Recreate' }, // Required for single-node with PVC
        selector: { matchLabels: selectorLabels },
        template: {
          metadata: { labels },
          spec: {
            securityContext: {
              fsGroup: 10001,
              runAsUser: 10001,
              runAsNonRoot: true,
            },
            containers: [
              {
                name: 'pyroscope',
                image,
                ports: [
                  { containerPort: 4040, name: 'http' },
                ],
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ],
                resources: toK8sResources(resources),
                readinessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(4040),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(4040),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                },
              },
            ],
            volumes: [
              {
                name: 'data',
                persistentVolumeClaim: { claimName: 'pyroscope-data' },
              },
            ],
          },
        },
      },
    });

    // Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'pyroscope',
        namespace,
        labels,
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 4040,
            targetPort: k8s.IntOrString.fromNumber(4040),
          },
        ],
        selector: selectorLabels,
      },
    });
  }
}
