import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import * as images from '../../../.env-files/images.json';

export interface BackstageHostChartProps extends ChartProps {}

/**
 * Backstage deployment that targets the host cluster (no vcluster indirection).
 * Provides the base resources consumed both in production and by DevSpace when
 * swapping the container image for local development.
 */
export class BackstageHostChart extends Chart {
  constructor(scope: Construct, id: string, props?: BackstageHostChartProps) {
    super(scope, id, props);

    const namespace = 'backstage';
    const appName = 'backstage';
    const environmentLabel = 'host';
    const postgresName = 'postgresql-backstage';
    const ingressHost = 'cnoe.localtest.me';

    const imageRef = images.production?.backstage ?? images.dev.backstage;

    const sanitizeLabel = (value: string) =>
      value
        .toLowerCase()
        .replace(/[^a-z0-9._-]/g, '-')
        .slice(0, 63)
        .replace(/^-+|[-.]+$/g, '');

    const parseRepo = (img: string) => img.split('@')[0].split(':')[0];
    const parseTagOrDigest = (img: string) => {
      if (img.includes('@')) {
        const digest = img.split('@')[1];
        return digest.replace(':', '-');
      }
      if (img.includes(':')) {
        return img.split(':').pop() as string;
      }
      return 'latest';
    };

    const imageRepoLabel = sanitizeLabel(parseRepo(imageRef));
    const imageTagLabel = sanitizeLabel(parseTagOrDigest(imageRef));

    // Service Account
    new k8s.KubeServiceAccount(this, `${appName}-sa`, {
      metadata: {
        name: appName,
        namespace,
        labels: {
          app: appName,
          environment: environmentLabel,
        },
      },
    });

    // ClusterRole granting read across the cluster (for catalog, K8s plugin, etc.)
    new k8s.KubeClusterRole(this, `${appName}-read-all`, {
      metadata: {
        name: `${appName}-read-all`,
        labels: {
          app: appName,
          environment: environmentLabel,
        },
      },
      rules: [
        {
          apiGroups: ['*'],
          resources: ['*'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    new k8s.KubeClusterRoleBinding(this, `${appName}-read-all-binding`, {
      metadata: {
        name: `${appName}-read-all`,
        labels: {
          app: appName,
          environment: environmentLabel,
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: `${appName}-read-all`,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: appName,
          namespace,
        },
      ],
    });

    // Stable Service for Backstage backend
    new k8s.KubeService(this, `${appName}-service`, {
      metadata: {
        name: appName,
        namespace,
        labels: {
          app: appName,
          environment: environmentLabel,
        },
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
          environment: environmentLabel,
        },
      },
    });

    // Persistent Volume Claims reused by both devspace and in-cluster deployments
    const cacheAnnotations = {
      'argocd.argoproj.io/sync-options': 'ServerSideApply=true',
    };

    new k8s.KubePersistentVolumeClaim(this, `${appName}-home-cache`, {
      metadata: {
        name: `${appName}-home-cache`,
        namespace,
        annotations: cacheAnnotations,
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString('2Gi'),
          },
        },
      },
    });

    new k8s.KubePersistentVolumeClaim(this, `${appName}-home-local`, {
      metadata: {
        name: `${appName}-home-local`,
        namespace,
        annotations: cacheAnnotations,
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString('5Gi'),
          },
        },
      },
    });

    new k8s.KubePersistentVolumeClaim(this, `${appName}-nix-store`, {
      metadata: {
        name: `${appName}-nix-store`,
        namespace,
        annotations: cacheAnnotations,
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString('10Gi'),
          },
        },
      },
    });

    // Headless service to reach the Postgres StatefulSet
    new k8s.KubeService(this, `${postgresName}-service`, {
      metadata: {
        name: postgresName,
        namespace,
        labels: {
          app: postgresName,
        },
      },
      spec: {
        clusterIp: 'None',
        ports: [
          {
            name: 'postgres',
            port: 5432,
            targetPort: k8s.IntOrString.fromNumber(5432),
          },
        ],
        selector: {
          app: postgresName,
        },
      },
    });

    // Backstage Deployment
    new k8s.KubeDeployment(this, `${appName}-deployment`, {
      metadata: {
        name: appName,
        namespace,
        labels: {
          app: appName,
          environment: environmentLabel,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: appName,
            environment: environmentLabel,
          },
        },
        template: {
          metadata: {
            labels: {
              app: appName,
              environment: environmentLabel,
              'app.kubernetes.io/name': appName,
              'app.kubernetes.io/instance': environmentLabel,
              'app.kubernetes.io/part-of': 'developer-portal',
              'app.kubernetes.io/component': 'backend',
              'backstage.io/kubernetes-id': appName,
              'backstage.io/kubernetes-environment': environmentLabel,
              'backstage.io/kubernetes-version': imageTagLabel,
              'backstage.io/kubernetes-image': imageRepoLabel,
            },
          },
          spec: {
            serviceAccountName: appName,
            containers: [
              {
                name: appName,
                image: imageRef,
                imagePullPolicy: 'IfNotPresent',
                ports: [
                  {
                    containerPort: 7007,
                    name: 'http',
                  },
                ],
                env: [
                  {
                    name: 'NODE_ENV',
                    value: 'production',
                  },
                  {
                    name: 'APP_CONFIG_backend_baseUrl',
                    value: `https://${ingressHost}:8443`,
                  },
                  {
                    name: 'APP_CONFIG_backend_listen_port',
                    value: '7007',
                  },
                  {
                    name: 'APP_CONFIG_app_baseUrl',
                    value: `https://${ingressHost}:8443`,
                  },
                ],
                volumeMounts: [
                  {
                    name: 'cache',
                    mountPath: '/app/.backstage/cache',
                  },
                  {
                    name: 'local',
                    mountPath: '/app/.local',
                  },
                  {
                    name: 'nix-store',
                    mountPath: '/nix/store',
                  },
                ],
              },
            ],
            volumes: [
              {
                name: 'cache',
                persistentVolumeClaim: {
                  claimName: `${appName}-home-cache`,
                },
              },
              {
                name: 'local',
                persistentVolumeClaim: {
                  claimName: `${appName}-home-local`,
                },
              },
              {
                name: 'nix-store',
                persistentVolumeClaim: {
                  claimName: `${appName}-nix-store`,
                },
              },
            ],
          },
        },
      },
    });

    // Ingress for Backstage
    new k8s.KubeIngress(this, `${appName}-ingress`, {
      metadata: {
        name: `${appName}-ingress`,
        namespace,
        annotations: {
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          'kubernetes.io/ingress.class': 'nginx',
        },
      },
      spec: {
        tls: [
          {
            hosts: [ingressHost],
            secretName: 'backstage-tls',
          },
        ],
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
                      name: appName,
                      port: {
                        number: 7007,
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
