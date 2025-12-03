/**
 * LangfuseChart - Langfuse LLM Observability Platform
 *
 * Deploys Langfuse v2.95.1 self-hosted with PostgreSQL backend.
 * Note: Using v2 because v3 requires ClickHouse. v2 only needs PostgreSQL.
 * - Connects to langfuse-postgres service
 * - Auth secrets from langfuse-auth
 * - Ingress for local access via langfuse.cnoe.localtest.me
 *
 * Sync wave: -60 (after PostgreSQL at -65)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface LangfuseChartProps extends ChartProps {
  /**
   * Namespace for Langfuse deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Langfuse image version
   * @default '2.95.1' (v2.x only requires PostgreSQL, v3.x requires ClickHouse)
   */
  imageVersion?: string;

  /**
   * PostgreSQL service hostname
   * @default 'langfuse-postgres'
   */
  postgresHost?: string;

  /**
   * PostgreSQL port
   * @default 5432
   */
  postgresPort?: number;

  /**
   * Database name
   * @default 'langfuse'
   */
  databaseName?: string;

  /**
   * Credentials secret name
   * @default 'langfuse-postgres-credentials'
   */
  credentialsSecretName?: string;

  /**
   * Auth secret name
   * @default 'langfuse-auth'
   */
  authSecretName?: string;

  /**
   * Ingress hostname
   * @default 'langfuse.cnoe.localtest.me'
   */
  ingressHost?: string;

  /**
   * NEXTAUTH_URL base URL
   * @default 'https://langfuse.cnoe.localtest.me:8443'
   */
  nextAuthUrl?: string;
}

export class LangfuseChart extends Chart {
  constructor(scope: Construct, id: string, props?: LangfuseChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'observability';
    const imageVersion = props?.imageVersion || '2.95.1';
    const postgresHost = props?.postgresHost || 'langfuse-postgres';
    const postgresPort = props?.postgresPort || 5432;
    const databaseName = props?.databaseName || 'langfuse';
    const credentialsSecretName = props?.credentialsSecretName || 'langfuse-postgres-credentials';
    const authSecretName = props?.authSecretName || 'langfuse-auth';
    const ingressHost = props?.ingressHost || 'langfuse.cnoe.localtest.me';
    const nextAuthUrl = props?.nextAuthUrl || 'https://langfuse.cnoe.localtest.me:8443';

    const labels = {
      'app': 'langfuse',
      'app.kubernetes.io/name': 'langfuse',
      'app.kubernetes.io/component': 'llm-observability',
      'app.kubernetes.io/part-of': 'observability',
    };

    // Langfuse Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'langfuse',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-60',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'langfuse',
          },
        },
        template: {
          metadata: {
            labels,
          },
          spec: {
            securityContext: {
              runAsNonRoot: true,
              runAsUser: 1000,
              runAsGroup: 1000,
              fsGroup: 1000,
            },
            containers: [
              {
                name: 'langfuse',
                image: `langfuse/langfuse:${imageVersion}`,
                ports: [
                  { containerPort: 3000, name: 'http', protocol: 'TCP' },
                ],
                env: [
                  // Database connection via constructed URL
                  {
                    name: 'POSTGRES_USER',
                    valueFrom: {
                      secretKeyRef: {
                        name: credentialsSecretName,
                        key: 'POSTGRES_USER',
                      },
                    },
                  },
                  {
                    name: 'POSTGRES_PASSWORD',
                    valueFrom: {
                      secretKeyRef: {
                        name: credentialsSecretName,
                        key: 'POSTGRES_PASSWORD',
                      },
                    },
                  },
                  {
                    name: 'DATABASE_URL',
                    value: `postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@${postgresHost}:${postgresPort}/${databaseName}`,
                  },
                  // NextAuth configuration
                  {
                    name: 'NEXTAUTH_URL',
                    value: nextAuthUrl,
                  },
                  {
                    name: 'NEXTAUTH_SECRET',
                    valueFrom: {
                      secretKeyRef: {
                        name: authSecretName,
                        key: 'NEXTAUTH_SECRET',
                      },
                    },
                  },
                  // Langfuse specific secrets
                  {
                    name: 'SALT',
                    valueFrom: {
                      secretKeyRef: {
                        name: authSecretName,
                        key: 'SALT',
                      },
                    },
                  },
                  {
                    name: 'ENCRYPTION_KEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: authSecretName,
                        key: 'ENCRYPTION_KEY',
                      },
                    },
                  },
                  // Enable telemetry for self-hosted
                  {
                    name: 'TELEMETRY_ENABLED',
                    value: 'false',
                  },
                  // Disable sign-ups after initial admin (optional)
                  {
                    name: 'AUTH_DISABLE_SIGNUP',
                    value: 'false',
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('1Gi'),
                    cpu: k8s.Quantity.fromString('500m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('3Gi'),
                    cpu: k8s.Quantity.fromString('2000m'),
                  },
                },
                readinessProbe: {
                  httpGet: {
                    path: '/api/public/health',
                    port: k8s.IntOrString.fromNumber(3000),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/api/public/health',
                    port: k8s.IntOrString.fromNumber(3000),
                  },
                  initialDelaySeconds: 60,
                  periodSeconds: 30,
                },
              },
            ],
          },
        },
      },
    });

    // Langfuse Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'langfuse',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-60',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'langfuse' },
        ports: [
          {
            name: 'http',
            port: 3000,
            targetPort: k8s.IntOrString.fromNumber(3000),
            protocol: 'TCP',
          },
        ],
      },
    });

    // Ingress for local access
    new k8s.KubeIngress(this, 'ingress', {
      metadata: {
        name: 'langfuse',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-60',
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          'nginx.ingress.kubernetes.io/proxy-body-size': '50m',
          'nginx.ingress.kubernetes.io/proxy-read-timeout': '300',
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
                      name: 'langfuse',
                      port: {
                        number: 3000,
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
