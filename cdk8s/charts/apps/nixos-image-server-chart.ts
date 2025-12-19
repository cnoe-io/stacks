/**
 * NixOS Image Server Chart
 *
 * Deploys an nginx HTTP server serving qcow2 images for DataVolume imports.
 * The server hosts the pre-built NixOS kubevirt image from Docker Hub.
 *
 * User Story: US2 - Create NixOS-based VM Image
 * Requirements: FR-011 through FR-015 (Image Distribution)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface NixOsImageServerChartProps extends ChartProps {
  /**
   * Docker image containing nginx + qcow2 files
   *
   * Image must contain:
   * - nginx web server
   * - qcow2 file at /usr/share/nginx/html/nixos.qcow2
   *
   * Build locally with: build-nixos-image (or clnix) from cluster-menu.sh
   * This loads the image into Kind without needing a registry.
   *
   * @default "nixos-kubevirt-minimal:latest"
   */
  image?: string;

  /**
   * Number of replicas for image server deployment
   * @default 1
   */
  replicas?: number;

  /**
   * Target namespace for deployment
   * @default "default"
   */
  namespace?: string;

  /**
   * Image pull policy for the nginx + qcow2 image
   * Use `IfNotPresent` for locally-loaded Kind images.
   *
   * @default "IfNotPresent"
   */
  imagePullPolicy?: 'Always' | 'IfNotPresent' | 'Never';
}

export class NixOsImageServerChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsImageServerChartProps = {}) {
    super(scope, id, props);

    const {
      image = 'nixos-kubevirt-minimal:latest',
      replicas = 1,
      namespace = 'default',
      imagePullPolicy = 'IfNotPresent',
    } = props;

    const appName = 'nixos-image-server';
    // NOTE: Keep the legacy `app: <name>` selector for compatibility with
    // existing idpbuilder-generated repos/Applications. Deployment selectors are immutable.
    const selectorLabels = { app: appName };
    const labels = {
      ...selectorLabels,
      'app.kubernetes.io/name': appName,
      'app.kubernetes.io/component': 'image-server',
    };

    // Create Deployment for nginx image server
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: appName,
        namespace,
        labels,
        annotations: {
          // Deploy early in the sync wave (before DataVolumes need it)
          'argocd.argoproj.io/sync-wave': '-50',
        },
      },
      spec: {
        replicas,
        selector: {
          matchLabels: selectorLabels,
        },
        template: {
          metadata: {
            labels,
          },
          spec: {
            containers: [
              {
                name: 'nginx',
                image,
                imagePullPolicy,
                ports: [
                  {
                    name: 'http',
                    containerPort: 80,
                    protocol: 'TCP',
                  },
                ],
                readinessProbe: {
                  httpGet: {
                    path: '/nixos.qcow2',
                    port: k8s.IntOrString.fromNumber(80),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/nixos.qcow2',
                    port: k8s.IntOrString.fromNumber(80),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 20,
                },
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('100m'),
                    memory: k8s.Quantity.fromString('128Mi'),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('500m'),
                    memory: k8s.Quantity.fromString('512Mi'),
                  },
                },
              },
            ],
          },
        },
      },
    });

    // Create Service for the image server
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: appName,
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-50',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: selectorLabels,
        ports: [
          {
            name: 'http',
            protocol: 'TCP',
            port: 80,
            targetPort: k8s.IntOrString.fromNumber(80),
          },
        ],
      },
    });
  }
}
