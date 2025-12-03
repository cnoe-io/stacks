/**
 * LangfusePostgresChart - PostgreSQL Database for Langfuse
 *
 * Deploys PostgreSQL 16-alpine as the backend database for Langfuse.
 * - PVC for persistent storage (20Gi)
 * - Credentials from External Secrets (langfuse-postgres-credentials)
 *
 * Sync wave: -65 (same as Jaeger, before Langfuse)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface LangfusePostgresChartProps extends ChartProps {
  /**
   * Namespace for PostgreSQL deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * PostgreSQL image
   * @default 'postgres:16-alpine'
   */
  image?: string;

  /**
   * PVC storage size
   * @default '20Gi'
   */
  storageSize?: string;

  /**
   * Database name
   * @default 'langfuse'
   */
  databaseName?: string;

  /**
   * Secret name for credentials
   * @default 'langfuse-postgres-credentials'
   */
  credentialsSecretName?: string;
}

export class LangfusePostgresChart extends Chart {
  constructor(scope: Construct, id: string, props?: LangfusePostgresChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'observability';
    const image = props?.image || 'postgres:16-alpine';
    const storageSize = props?.storageSize || '20Gi';
    const databaseName = props?.databaseName || 'langfuse';
    const credentialsSecretName = props?.credentialsSecretName || 'langfuse-postgres-credentials';

    const labels = {
      'app': 'langfuse-postgres',
      'app.kubernetes.io/name': 'langfuse-postgres',
      'app.kubernetes.io/component': 'database',
      'app.kubernetes.io/part-of': 'observability',
    };

    // PersistentVolumeClaim for PostgreSQL data
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'langfuse-postgres-pvc',
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

    // PostgreSQL Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'langfuse-postgres',
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
            'app': 'langfuse-postgres',
          },
        },
        template: {
          metadata: {
            labels,
          },
          spec: {
            securityContext: {
              runAsUser: 999,
              runAsGroup: 999,
              fsGroup: 999,
            },
            containers: [
              {
                name: 'postgres',
                image,
                ports: [
                  { containerPort: 5432, name: 'postgres', protocol: 'TCP' },
                ],
                env: [
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
                    name: 'POSTGRES_DB',
                    value: databaseName,
                  },
                  {
                    name: 'PGDATA',
                    value: '/var/lib/postgresql/data/pgdata',
                  },
                ],
                volumeMounts: [
                  {
                    name: 'postgres-data',
                    mountPath: '/var/lib/postgresql/data',
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('256Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('1Gi'),
                    cpu: k8s.Quantity.fromString('500m'),
                  },
                },
                readinessProbe: {
                  exec: {
                    command: ['pg_isready', '-U', 'langfuse', '-d', databaseName],
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 5,
                },
                livenessProbe: {
                  exec: {
                    command: ['pg_isready', '-U', 'langfuse', '-d', databaseName],
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                },
              },
            ],
            volumes: [
              {
                name: 'postgres-data',
                persistentVolumeClaim: {
                  claimName: 'langfuse-postgres-pvc',
                },
              },
            ],
          },
        },
      },
    });

    // PostgreSQL Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'langfuse-postgres',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-65',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'langfuse-postgres' },
        ports: [
          {
            name: 'postgres',
            port: 5432,
            targetPort: k8s.IntOrString.fromNumber(5432),
            protocol: 'TCP',
          },
        ],
      },
    });
  }
}
