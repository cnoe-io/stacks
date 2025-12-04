/**
 * LangfuseChart - Langfuse LLM Observability Platform
 *
 * Deploys Langfuse v3 self-hosted with full infrastructure stack:
 * - PostgreSQL: Primary database
 * - ClickHouse: Analytics storage (langfuse-clickhouse)
 * - Redis: Caching (langfuse-redis)
 * - MinIO: Blob storage (langfuse-minio)
 * - Web container: Main application
 * - Worker container: Background job processing
 *
 * Auth secrets from langfuse-auth, headless initialization via langfuse-init.
 * Ingress for local access via langfuse.cnoe.localtest.me
 *
 * Sync wave: -60 (after infrastructure at -70)
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
   * @default '3'
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
   * ClickHouse service hostname
   * @default 'langfuse-clickhouse'
   */
  clickhouseHost?: string;

  /**
   * ClickHouse user (statically configured to work around K8s env substitution limitations)
   * @default 'default'
   */
  clickhouseUser?: string;

  /**
   * ClickHouse password (statically configured to work around K8s env substitution limitations)
   * @default 'clickhouse_langfuse_password'
   */
  clickhousePassword?: string;

  /**
   * Redis service hostname
   * @default 'langfuse-redis'
   */
  redisHost?: string;

  /**
   * MinIO service hostname
   * @default 'langfuse-minio'
   */
  minioHost?: string;

  /**
   * MinIO root user (statically configured to work around K8s env substitution limitations)
   * @default 'minio'
   */
  minioUser?: string;

  /**
   * MinIO root password (statically configured to work around K8s env substitution limitations)
   * @default 'minio_langfuse_password'
   */
  minioPassword?: string;

  /**
   * Credentials secret name
   * @default 'langfuse-postgres-credentials'
   */
  credentialsSecretName?: string;

  /**
   * ClickHouse credentials secret name
   * @default 'langfuse-clickhouse-credentials'
   */
  clickhouseCredentialsSecretName?: string;

  /**
   * MinIO credentials secret name
   * @default 'langfuse-minio-credentials'
   */
  minioCredentialsSecretName?: string;

  /**
   * Auth secret name
   * @default 'langfuse-auth'
   */
  authSecretName?: string;

  /**
   * Headless initialization secret name (contains LANGFUSE_INIT_* vars)
   * @default 'langfuse-init'
   */
  initSecretName?: string;

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
    const imageVersion = props?.imageVersion || '3';
    const postgresHost = props?.postgresHost || 'langfuse-postgres';
    const postgresPort = props?.postgresPort || 5432;
    const databaseName = props?.databaseName || 'langfuse';
    const clickhouseHost = props?.clickhouseHost || 'langfuse-clickhouse';
    const clickhouseUser = props?.clickhouseUser || 'default';
    const clickhousePassword = props?.clickhousePassword || 'clickhouse_langfuse_password';
    const redisHost = props?.redisHost || 'langfuse-redis';
    const minioHost = props?.minioHost || 'langfuse-minio';
    const minioUser = props?.minioUser || 'minio';
    const minioPassword = props?.minioPassword || 'minio_langfuse_password';
    const credentialsSecretName = props?.credentialsSecretName || 'langfuse-postgres-credentials';
    const _clickhouseCredentialsSecretName = props?.clickhouseCredentialsSecretName || 'langfuse-clickhouse-credentials';
    const _minioCredentialsSecretName = props?.minioCredentialsSecretName || 'langfuse-minio-credentials';
    const authSecretName = props?.authSecretName || 'langfuse-auth';
    const initSecretName = props?.initSecretName || 'langfuse-init';
    const ingressHost = props?.ingressHost || 'langfuse.cnoe.localtest.me';
    const nextAuthUrl = props?.nextAuthUrl || 'https://langfuse.cnoe.localtest.me:8443';

    const labels = {
      'app': 'langfuse',
      'app.kubernetes.io/name': 'langfuse',
      'app.kubernetes.io/component': 'llm-observability',
      'app.kubernetes.io/part-of': 'observability',
    };

    const workerLabels = {
      'app': 'langfuse-worker',
      'app.kubernetes.io/name': 'langfuse-worker',
      'app.kubernetes.io/component': 'llm-observability',
      'app.kubernetes.io/part-of': 'observability',
    };

    // Common environment variables for both web and worker
    // Note: Using static values for credentials in URLs because Kubernetes $(VAR) substitution
    // doesn't work when the referenced variable comes from valueFrom (secretKeyRef).
    // Only $(VAR) syntax for variables defined as literal 'value:' works.
    const commonEnv: k8s.EnvVar[] = [
      // Database connection - uses $(VAR) substitution (works because POSTGRES_USER/PASSWORD come first)
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
      // ClickHouse connection - use static values (K8s env substitution limitation)
      // CLICKHOUSE_USER/PASSWORD required by migration script, CLICKHOUSE_URL used by app
      {
        name: 'CLICKHOUSE_USER',
        value: clickhouseUser,
      },
      {
        name: 'CLICKHOUSE_PASSWORD',
        value: clickhousePassword,
      },
      {
        name: 'CLICKHOUSE_URL',
        value: `http://${clickhouseUser}:${clickhousePassword}@${clickhouseHost}:8123`,
      },
      {
        name: 'CLICKHOUSE_MIGRATION_URL',
        value: `clickhouse://${clickhouseUser}:${clickhousePassword}@${clickhouseHost}:9000`,
      },
      // Redis connection
      {
        name: 'REDIS_HOST',
        value: redisHost,
      },
      {
        name: 'REDIS_PORT',
        value: '6379',
      },
      // MinIO/S3 connection - use static values (K8s env substitution limitation)
      {
        name: 'LANGFUSE_S3_BUCKET_NAME',
        value: 'langfuse',
      },
      {
        name: 'LANGFUSE_S3_ENDPOINT',
        value: `http://${minioHost}:9000`,
      },
      {
        name: 'LANGFUSE_S3_ACCESS_KEY_ID',
        value: minioUser,
      },
      {
        name: 'LANGFUSE_S3_SECRET_ACCESS_KEY',
        value: minioPassword,
      },
      {
        name: 'LANGFUSE_S3_REGION',
        value: 'us-east-1',
      },
      {
        name: 'LANGFUSE_S3_FORCE_PATH_STYLE',
        value: 'true',
      },
      {
        name: 'LANGFUSE_S3_EVENT_UPLOAD_BUCKET',
        value: 'langfuse',
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
      // Langfuse secrets
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
      // ClickHouse single-node mode (no Zookeeper/cluster)
      // Required for single-node ClickHouse deployments without Zookeeper
      {
        name: 'CLICKHOUSE_CLUSTER_ENABLED',
        value: 'false',
      },
      // Settings
      {
        name: 'TELEMETRY_ENABLED',
        value: 'false',
      },
      {
        name: 'AUTH_DISABLE_SIGNUP',
        value: 'false',
      },
    ];

    // Langfuse Web Deployment
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
                env: commonEnv,
                // Mount headless initialization secrets as environment variables
                envFrom: [
                  {
                    secretRef: {
                      name: initSecretName,
                      optional: true,
                    },
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
                  initialDelaySeconds: 60,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/api/public/health',
                    port: k8s.IntOrString.fromNumber(3000),
                  },
                  initialDelaySeconds: 90,
                  periodSeconds: 30,
                },
              },
            ],
          },
        },
      },
    });

    // Langfuse Worker Deployment (v3 requirement)
    new k8s.KubeDeployment(this, 'worker-deployment', {
      metadata: {
        name: 'langfuse-worker',
        namespace,
        labels: workerLabels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-60',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'langfuse-worker',
          },
        },
        template: {
          metadata: {
            labels: workerLabels,
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
                name: 'langfuse-worker',
                image: `langfuse/langfuse-worker:${imageVersion}`,
                env: commonEnv,
                envFrom: [
                  {
                    secretRef: {
                      name: initSecretName,
                      optional: true,
                    },
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('512Mi'),
                    cpu: k8s.Quantity.fromString('250m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('2Gi'),
                    cpu: k8s.Quantity.fromString('1000m'),
                  },
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
