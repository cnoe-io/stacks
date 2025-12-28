/**
 * CaipeRagWebuiChart - RAG WebUI for CAIPE
 *
 * Deploys the RAG WebUI React application that provides:
 * - Document upload interface
 * - Knowledge base query interface
 * - Ingestion metrics dashboard
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  getCaipeRagLabels,
  getCaipeIngressHost,
} from '../../lib/caipe-helpers';

export interface CaipeRagWebuiChartProps extends ChartProps {
  /**
   * Namespace for RAG WebUI
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * RAG WebUI image
   * @default 'ghcr.io/cnoe-io/rag-webui:0.2.4'
   */
  image?: string;

  /**
   * Base host for ingress
   * @default 'cnoe.localtest.me'
   */
  baseHost?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '0'
   */
  syncWave?: string;
}

export class CaipeRagWebuiChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeRagWebuiChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/caipe-rag-webui:latest';
    const baseHost = props.baseHost || process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.ragStack;

    const labels = getCaipeRagLabels('rag-webui');
    const selectorLabels = {
      'app.kubernetes.io/name': 'rag-webui',
      'app.kubernetes.io/instance': 'caipe-rag-webui',
    };

    const ingressHost = getCaipeIngressHost('rag-webui', baseHost);

    // Deployment for RAG WebUI
    new k8s.KubeDeployment(this, 'rag-webui', {
      metadata: {
        name: 'rag-webui',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: selectorLabels,
        },
        template: {
          metadata: {
            labels: { ...labels, ...selectorLabels },
          },
          spec: {
            containers: [
              {
                name: 'rag-webui',
                image: image,
                ports: [
                  {
                    name: 'http',
                    containerPort: CAIPE_PORTS.ragWebui,
                  },
                ],
                env: [
                  // RAG Server backend URL (internal service)
                  {
                    name: 'RAG_SERVER_URL',
                    value: `http://rag-server.${namespace}.svc.cluster.local:${CAIPE_PORTS.ragServer}`,
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('64Mi'),
                    cpu: k8s.Quantity.fromString('25m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('128Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                },
                livenessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragWebui),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 30,
                  timeoutSeconds: 5,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragWebui),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 10,
                  timeoutSeconds: 3,
                },
              },
            ],
          },
        },
      },
    });

    // Service for RAG WebUI
    new k8s.KubeService(this, 'rag-webui-svc', {
      metadata: {
        name: 'rag-webui',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: selectorLabels,
        ports: [
          {
            name: 'http',
            port: CAIPE_PORTS.ragWebui,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragWebui),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });

    // Ingress for RAG WebUI
    new k8s.KubeIngress(this, 'rag-webui-ingress', {
      metadata: {
        name: 'rag-webui',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          'nginx.ingress.kubernetes.io/proxy-body-size': '10m',
        },
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [
          {
            host: ingressHost,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'rag-webui',
                      port: {
                        number: CAIPE_PORTS.ragWebui,
                      },
                    },
                  },
                },
              ],
            },
          },
        ],
      },
    });
  }
}
