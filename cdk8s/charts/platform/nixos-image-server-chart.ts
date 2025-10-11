/**
 * NixOS Image Server Chart
 *
 * Deploys an nginx HTTP server to serve NixOS qcow2 images for DataVolume imports.
 * Uses hostPath volume to access images built on the host system.
 *
 * User Story: US2 - Create NixOS-based VM Image
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface NixOsImageServerChartProps extends ChartProps {
  /**
   * Host path containing qcow2 images
   * @default "/home/vpittamp/stacks/nixos-images"
   */
  hostPath?: string;

  /**
   * Number of replicas
   * @default 1
   */
  replicas?: number;
}

export class NixOsImageServerChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsImageServerChartProps = {}) {
    super(scope, id, props);

    const {
      hostPath = '/home/vpittamp/stacks/nixos-images',
      replicas = 1,
    } = props;

    const namespace = 'default';
    const name = 'nixos-image-server';

    // Deployment with nginx serving static files
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name,
        namespace,
        labels: {
          'app.kubernetes.io/name': name,
          'app.kubernetes.io/component': 'image-server',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-50',
        },
      },
      spec: {
        replicas,
        selector: {
          matchLabels: {
            app: name,
          },
        },
        template: {
          metadata: {
            labels: {
              app: name,
              'app.kubernetes.io/name': name,
            },
          },
          spec: {
            containers: [
              {
                name: 'nginx',
                image: 'nginx:alpine',
                ports: [
                  {
                    containerPort: 80,
                    name: 'http',
                  },
                ],
                volumeMounts: [
                  {
                    name: 'images',
                    mountPath: '/usr/share/nginx/html',
                    readOnly: true,
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('64Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('128Mi'),
                    cpu: k8s.Quantity.fromString('200m'),
                  },
                },
              },
            ],
            volumes: [
              {
                name: 'images',
                hostPath: {
                  path: hostPath,
                  type: 'Directory',
                },
              },
            ],
          },
        },
      },
    });

    // Service for HTTP access
    new k8s.KubeService(this, 'service', {
      metadata: {
        name,
        namespace,
        labels: {
          'app.kubernetes.io/name': name,
          'app.kubernetes.io/component': 'image-server',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-50',
        },
      },
      spec: {
        selector: {
          app: name,
        },
        ports: [
          {
            port: 80,
            targetPort: k8s.IntOrString.fromNumber(80),
            name: 'http',
          },
        ],
        type: 'ClusterIP',
      },
    });
  }
}
