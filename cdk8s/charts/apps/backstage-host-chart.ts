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
    const postgresName = 'postgresql';
    const ingressHost = 'cnoe.localtest.me';
    const baseUrl = `https://${ingressHost}:8443`;

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
            storage: k8s.Quantity.fromString('20Gi'),
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
            storage: k8s.Quantity.fromString('20Gi'),
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
            storage: k8s.Quantity.fromString('100Gi'),
          },
        },
      },
    });

    // Backstage Kubernetes plugin configuration secret
    new k8s.KubeSecret(this, `${appName}-k8s-config`, {
      metadata: {
        name: `${appName}-k8s-config`,
        namespace,
        labels: {
          app: appName,
          environment: environmentLabel,
        },
      },
      stringData: {
        'k8s-config.yaml': `type: 'config'\nclusters:\n  - url: https://kubernetes.default.svc.cluster.local\n    name: host-cluster\n    authProvider: 'serviceAccount'\n    skipTLSVerify: true\n    skipMetricsLookup: true\n    serviceAccountToken:\n      $file: /var/run/secrets/kubernetes.io/serviceaccount/token\n    caData:\n      $file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
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

    new k8s.KubeStatefulSet(this, `${postgresName}-statefulset`, {
      metadata: {
        name: postgresName,
        namespace,
        labels: {
          app: postgresName,
        },
      },
      spec: {
        serviceName: postgresName,
        replicas: 1,
        selector: {
          matchLabels: {
            app: postgresName,
          },
        },
        template: {
          metadata: {
            labels: {
              app: postgresName,
            },
          },
          spec: {
            containers: [
              {
                name: 'postgresql',
                image: 'postgres:16',
                ports: [{ containerPort: 5432 }],
                env: [
                  { name: 'POSTGRES_DB', value: 'backstage' },
                  { name: 'POSTGRES_USER', value: 'backstage' },
                  { name: 'POSTGRES_PASSWORD', value: 'changeme123' },
                ],
                volumeMounts: [
                  {
                    name: 'postgres-storage',
                    mountPath: '/var/lib/postgresql/data',
                  },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('100m'),
                    memory: k8s.Quantity.fromString('256Mi'),
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
        volumeClaimTemplates: [
          {
            metadata: {
              name: 'postgres-storage',
            },
            spec: {
              accessModes: ['ReadWriteOnce'],
              resources: {
                requests: {
                  storage: k8s.Quantity.fromString('10Gi'),
                },
              },
            },
          },
        ],
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
                envFrom: [
                  { secretRef: { name: 'backstage-env-vars' } },
                ],
                env: [
                  { name: 'LOG_LEVEL', value: 'info' },
                  { name: 'NODE_ENV', value: 'production' },
                  { name: 'NODE_TLS_REJECT_UNAUTHORIZED', value: '0' },
                  { name: 'ENVIRONMENT', value: environmentLabel },
                  { name: 'APP_CONFIG_app_baseUrl', value: baseUrl },
                  { name: 'APP_CONFIG_backend_baseUrl', value: baseUrl },
                  { name: 'APP_CONFIG_backend_cors_origin', value: baseUrl },
                  { name: 'APP_CONFIG_app_signIn_provider', value: 'keycloak-oidc' },
                  { name: 'APP_CONFIG_app_signIn_auto', value: 'true' },
                  { name: 'APP_CONFIG_auth_environment', value: 'production' },
                  { name: 'APP_CONFIG_agentForge_baseUrl', value: 'https://ai-platform-engineering.cnoe.localtest.me:8443' },
                ],
                volumeMounts: [
                  { name: 'k8s-config', mountPath: '/app/k8s-config.yaml', subPath: 'k8s-config.yaml' },
                  { name: 'nix-store', mountPath: '/nix' },
                  { name: 'home-cache', mountPath: '/home/code/.cache' },
                  { name: 'home-local', mountPath: '/home/code/.local' },
                ],
              },
            ],
            volumes: [
              { name: 'k8s-config', secret: { secretName: `${appName}-k8s-config` } },
              { name: 'nix-store', persistentVolumeClaim: { claimName: `${appName}-nix-store` } },
              { name: 'home-cache', persistentVolumeClaim: { claimName: `${appName}-home-cache` } },
              { name: 'home-local', persistentVolumeClaim: { claimName: `${appName}-home-local` } },
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
