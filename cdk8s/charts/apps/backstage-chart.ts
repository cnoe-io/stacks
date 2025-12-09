import { Construct } from 'constructs';
import { Chart, ChartProps } from 'cdk8s';
import * as k8s from '../../imports/k8s';

export interface BackstageChartProps extends ChartProps {
  // Namespace for Backstage (default: backstage)
  namespace?: string;
  // Backstage image (default: docker.io/vpittamp23/backstage:1.0.4)
  image?: string;
  // PostgreSQL image (default: docker.io/library/postgres:15.3-alpine3.18)
  postgresImage?: string;
  // PostgreSQL storage size (default: 500Mi)
  postgresStorageSize?: string;
  // Ingress hosts (default: ['localhost', 'cnoe.localtest.me'])
  ingressHosts?: string[];
}

/**
 * BackstageChart - Backstage Developer Portal
 *
 * Creates 11 resources:
 * 1. Namespace: backstage
 * 2. ServiceAccount: backstage
 * 3. ClusterRole: backstage-argo-worfklows (typo maintained for compatibility)
 * 4. ClusterRole: read-all
 * 5. ClusterRoleBinding: backstage-argo-worfklows
 * 6. ClusterRoleBinding: backstage-read-all
 * 7. Service: backstage (port 7007)
 * 8. Service: postgresql (headless, port 5432)
 * 9. Deployment: backstage (sync-wave 20)
 * 10. StatefulSet: postgresql (sync-wave 10)
 * 11. Ingress: backstage
 */
export class BackstageChart extends Chart {
  constructor(scope: Construct, id: string, props: BackstageChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace ?? 'backstage';
    const backstageImage = props.image ?? 'docker.io/vpittamp23/backstage:1.0.4';
    const postgresImage = props.postgresImage ?? 'docker.io/library/postgres:15.3-alpine3.18';
    const postgresStorageSize = props.postgresStorageSize ?? '500Mi';
    const ingressHosts = props.ingressHosts ?? ['localhost', 'cnoe.localtest.me'];

    const appName = 'backstage';
    const postgresAppName = 'postgresql';

    // ==========================================================================
    // Namespace
    // ==========================================================================

    new k8s.KubeNamespace(this, 'backstage-namespace', {
      metadata: {
        name: namespace,
        labels: {
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // ==========================================================================
    // ServiceAccount
    // ==========================================================================

    new k8s.KubeServiceAccount(this, 'backstage-sa', {
      metadata: {
        name: appName,
        namespace,
      },
    });

    // ==========================================================================
    // ClusterRoles
    // ==========================================================================

    // ClusterRole: backstage-argo-worfklows (typo maintained for ref-implementation compatibility)
    new k8s.KubeClusterRole(this, 'backstage-argo-workflows-cr', {
      metadata: {
        name: 'backstage-argo-worfklows',
      },
      rules: [
        {
          apiGroups: ['argoproj.io'],
          resources: ['workflows'],
          verbs: ['create'],
        },
      ],
    });

    // ClusterRole: read-all
    new k8s.KubeClusterRole(this, 'backstage-read-all-cr', {
      metadata: {
        name: 'read-all',
      },
      rules: [
        {
          apiGroups: ['*'],
          resources: ['*'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // ==========================================================================
    // ClusterRoleBindings
    // ==========================================================================

    // ClusterRoleBinding: backstage-argo-worfklows
    new k8s.KubeClusterRoleBinding(this, 'backstage-argo-workflows-crb', {
      metadata: {
        name: 'backstage-argo-worfklows',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'backstage-argo-worfklows',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: appName,
          namespace,
        },
      ],
    });

    // ClusterRoleBinding: backstage-read-all
    new k8s.KubeClusterRoleBinding(this, 'backstage-read-all-crb', {
      metadata: {
        name: 'backstage-read-all',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'read-all',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: appName,
          namespace,
        },
      ],
    });

    // ==========================================================================
    // Services
    // ==========================================================================

    // Service: backstage (port 7007)
    new k8s.KubeService(this, 'backstage-service', {
      metadata: {
        name: appName,
        namespace,
      },
      spec: {
        ports: [
          {
            name: 'http',
            port: 7007,
            targetPort: k8s.IntOrString.fromString('http'),
          },
        ],
        selector: {
          app: appName,
        },
      },
    });

    // Service: postgresql (headless, port 5432)
    new k8s.KubeService(this, 'postgresql-service', {
      metadata: {
        name: postgresAppName,
        namespace,
        labels: {
          app: postgresAppName,
        },
      },
      spec: {
        clusterIp: 'None',
        ports: [
          {
            name: 'postgres',
            port: 5432,
          },
        ],
        selector: {
          app: postgresAppName,
        },
      },
    });

    // ==========================================================================
    // StatefulSet: PostgreSQL (sync-wave: 10)
    // ==========================================================================

    new k8s.KubeStatefulSet(this, 'postgresql-statefulset', {
      metadata: {
        name: postgresAppName,
        namespace,
        labels: {
          app: postgresAppName,
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '10',
        },
      },
      spec: {
        replicas: 1,
        serviceName: `service-${postgresAppName}`,
        selector: {
          matchLabels: {
            app: postgresAppName,
          },
        },
        template: {
          metadata: {
            labels: {
              app: postgresAppName,
            },
          },
          spec: {
            containers: [
              {
                name: 'postgres',
                image: postgresImage,
                ports: [
                  {
                    containerPort: 5432,
                    name: 'postgresdb',
                  },
                ],
                env: [
                  {
                    name: 'POSTGRES_DB',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'backstage-env-vars',
                        key: 'POSTGRES_DB',
                      },
                    },
                  },
                  {
                    name: 'POSTGRES_USER',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'backstage-env-vars',
                        key: 'POSTGRES_USER',
                      },
                    },
                  },
                  {
                    name: 'POSTGRES_PASSWORD',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'backstage-env-vars',
                        key: 'POSTGRES_PASSWORD',
                      },
                    },
                  },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('100m'),
                    memory: k8s.Quantity.fromString('300Mi'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('500Mi'),
                  },
                },
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/var/lib/postgresql/data',
                  },
                ],
              },
            ],
          },
        },
        volumeClaimTemplates: [
          {
            metadata: {
              name: 'data',
            },
            spec: {
              accessModes: ['ReadWriteOnce'],
              resources: {
                requests: {
                  storage: k8s.Quantity.fromString(postgresStorageSize),
                },
              },
            },
          },
        ],
      },
    });

    // ==========================================================================
    // Deployment: Backstage (sync-wave: 20)
    // ==========================================================================

    new k8s.KubeDeployment(this, 'backstage-deployment', {
      metadata: {
        name: appName,
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: appName,
          },
        },
        template: {
          metadata: {
            labels: {
              app: appName,
            },
          },
          spec: {
            serviceAccountName: appName,
            imagePullSecrets: [
              {
                name: 'ghcr-dockercfg',
              },
            ],
            containers: [
              {
                name: appName,
                image: backstageImage,
                ports: [
                  {
                    containerPort: 7007,
                    name: 'http',
                  },
                ],
                env: [
                  {
                    name: 'LOG_LEVEL',
                    value: 'debug',
                  },
                  {
                    name: 'NODE_TLS_REJECT_UNAUTHORIZED',
                    value: '0',
                  },
                  {
                    name: 'NODE_ENV',
                    value: 'production',
                  },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: 'backstage-env-vars',
                    },
                  },
                  {
                    secretRef: {
                      name: 'gitea-credentials',
                    },
                  },
                  {
                    secretRef: {
                      name: 'argocd-credentials',
                    },
                  },
                ],
              },
            ],
          },
        },
      },
    });

    // ==========================================================================
    // Ingress
    // ==========================================================================

    new k8s.KubeIngress(this, 'backstage-ingress', {
      metadata: {
        name: appName,
        namespace,
      },
      spec: {
        ingressClassName: 'nginx',
        rules: ingressHosts.map(host => ({
          host,
          http: {
            paths: [
              {
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: appName,
                    port: {
                      name: 'http',
                    },
                  },
                },
              },
            ],
          },
        })),
      },
    });
  }
}
