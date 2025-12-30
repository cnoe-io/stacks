/**
 * JaegerChart - Jaeger All-in-One Distributed Tracing
 *
 * Deploys Jaeger v1.66.0 all-in-one with Badger embedded storage.
 * - PVC for persistent Badger storage (10Gi)
 * - Services: query (16686), collector (9411 Zipkin)
 * - Ingress for local access via jaeger.cnoe.localtest.me
 *
 * Sync wave: -65 (after namespace and secrets)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface JaegerChartProps extends ChartProps {
  /**
   * Namespace for Jaeger deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Jaeger image version
   * @default '1.66.0'
   */
  imageVersion?: string;

  /**
   * PVC storage size for Badger
   * @default '10Gi'
   */
  storageSize?: string;

  /**
   * Span storage TTL (retention period)
   * @default '168h' (7 days)
   */
  spanStorageTtl?: string;

  /**
   * Ingress hostname
   * @default 'jaeger.<INGRESS_HOST>'
   */
  ingressHost?: string;
}

export class JaegerChart extends Chart {
  constructor(scope: Construct, id: string, props?: JaegerChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'observability';
    const imageVersion = props?.imageVersion || '1.66.0';
    const storageSize = props?.storageSize || '10Gi';
    const spanStorageTtl = props?.spanStorageTtl || '168h';
    const baseHost = process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const ingressHost = props?.ingressHost || `jaeger.${baseHost}`;

    const labels = {
      'app': 'jaeger',
      'app.kubernetes.io/name': 'jaeger',
      'app.kubernetes.io/component': 'tracing',
      'app.kubernetes.io/part-of': 'observability',
    };

    // PersistentVolumeClaim for Badger storage
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'jaeger-badger-pvc',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-65',
        },
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

    // Jaeger Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'jaeger',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-65',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'jaeger',
          },
        },
        template: {
          metadata: {
            labels,
          },
          spec: {
            securityContext: {
              runAsUser: 1000,
              runAsGroup: 1000,
              fsGroup: 1000,
            },
            containers: [
              {
                name: 'jaeger',
                image: `jaegertracing/all-in-one:${imageVersion}`,
                ports: [
                  { containerPort: 16686, name: 'query', protocol: 'TCP' },
                  { containerPort: 9411, name: 'zipkin', protocol: 'TCP' },
                  { containerPort: 14268, name: 'otlp-http', protocol: 'TCP' },
                  { containerPort: 14250, name: 'otlp-grpc', protocol: 'TCP' },
                ],
                env: [
                  { name: 'SPAN_STORAGE_TYPE', value: 'badger' },
                  { name: 'BADGER_EPHEMERAL', value: 'false' },
                  { name: 'BADGER_DIRECTORY_KEY', value: '/badger/key' },
                  { name: 'BADGER_DIRECTORY_VALUE', value: '/badger/value' },
                  { name: 'BADGER_SPAN_STORAGE_TTL', value: spanStorageTtl },
                  { name: 'BADGER_DEPENDENCY_STORAGE_TTL', value: spanStorageTtl },
                  // Enable Zipkin HTTP endpoint for Dapr traces
                  { name: 'COLLECTOR_ZIPKIN_HOST_PORT', value: ':9411' },
                ],
                volumeMounts: [
                  {
                    name: 'badger-data',
                    mountPath: '/badger',
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('512Mi'),
                    cpu: k8s.Quantity.fromString('500m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('2Gi'),
                    cpu: k8s.Quantity.fromString('2'),
                  },
                },
                // Use startup probe for slow-starting containers
                // Use admin health endpoint (14269) which starts earlier than UI (16686)
                startupProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(14269),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                  failureThreshold: 60,  // Allow up to 10 minutes to start
                },
                readinessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(16686),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(16686),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 10,
                  failureThreshold: 3,
                },
              },
            ],
            volumes: [
              {
                name: 'badger-data',
                persistentVolumeClaim: {
                  claimName: 'jaeger-badger-pvc',
                },
              },
            ],
          },
        },
      },
    });

    // Jaeger Query Service (UI access)
    new k8s.KubeService(this, 'service-query', {
      metadata: {
        name: 'jaeger-query',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-65',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'jaeger' },
        ports: [
          {
            name: 'query',
            port: 16686,
            targetPort: k8s.IntOrString.fromNumber(16686),
            protocol: 'TCP',
          },
        ],
      },
    });

    // Jaeger Collector Service (for Dapr Zipkin traces)
    new k8s.KubeService(this, 'service-collector', {
      metadata: {
        name: 'jaeger-collector',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-65',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'jaeger' },
        ports: [
          {
            name: 'zipkin',
            port: 9411,
            targetPort: k8s.IntOrString.fromNumber(9411),
            protocol: 'TCP',
          },
          {
            name: 'otlp-http',
            port: 14268,
            targetPort: k8s.IntOrString.fromNumber(14268),
            protocol: 'TCP',
          },
          {
            name: 'otlp-grpc',
            port: 14250,
            targetPort: k8s.IntOrString.fromNumber(14250),
            protocol: 'TCP',
          },
        ],
      },
    });

    // Ingress for local access
    new k8s.KubeIngress(this, 'ingress', {
      metadata: {
        name: 'jaeger',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-65',
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
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
                      name: 'jaeger-query',
                      port: {
                        number: 16686,
                      },
                    },
                  },
                },
              ],
            },
          },
        ],
        tls: [
          {
            hosts: [ingressHost],
          },
        ],
      },
    });
  }
}
