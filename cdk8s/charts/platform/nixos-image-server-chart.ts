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

export interface NixOsImageServerPlatformChartProps extends ChartProps {
  /**
   * Docker image containing qcow2 files
   * Build locally with: build-nixos-image (or clnix) from cluster-menu.sh
   * @default "nixos-kubevirt-minimal:latest"
   */
  image?: string;

  /**
   * Number of replicas
   * @default 1
   */
  replicas?: number;
}

export class NixOsImageServerPlatformChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsImageServerPlatformChartProps = {}) {
    super(scope, id, props);

    const {
      image = 'nixos-kubevirt-minimal:latest',
      replicas = 1,
    } = props;

    const namespace = 'default';
    const name = 'nixos-image-server';

    // Deployment using public Docker image containing nginx + qcow2
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
                image,  // Uses public Docker image with qcow2 files
                ports: [
                  {
                    containerPort: 80,
                    name: 'http',
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('128Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('2Gi'),  // Image is ~1.7GB
                    cpu: k8s.Quantity.fromString('200m'),
                  },
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
