import { Construct } from 'constructs';
import { Chart, ChartProps } from 'cdk8s';
import * as k8s from '../../imports/k8s';

export interface BackstageProxyConfig {
  // Base host for proxy targets (e.g., 'ai401kchat.com' for Talos)
  // This overrides the default cnoe.localtest.me proxy targets in the image
  baseHost: string;
  // Port for proxy targets (default: 8443)
  port?: number;
  // Use HTTPS for proxy targets (default: true)
  https?: boolean;
}

export interface BackstageChartProps extends ChartProps {
  // Namespace for Backstage (default: backstage)
  namespace?: string;
  // Backstage image (default: docker.io/vpittamp23/backstage:1.1.0)
  image?: string;
  // PostgreSQL image (default: docker.io/library/postgres:15.3-alpine3.18)
  postgresImage?: string;
  // PostgreSQL storage size (default: 500Mi)
  postgresStorageSize?: string;
  // Ingress hosts (default: ['localhost', 'cnoe.localtest.me'])
  ingressHosts?: string[];
  // TLS configuration for ingress
  tls?: {
    // Enable TLS (default: false)
    enabled: boolean;
    // Secret name for TLS certificate
    secretName?: string;
    // Cluster issuer name for cert-manager (e.g., 'letsencrypt-cloudflare')
    clusterIssuer?: string;
  };
  // Proxy configuration override for non-KIND clusters
  // When specified, creates a ConfigMap with app-config overlay to override proxy targets
  proxyConfig?: BackstageProxyConfig;
  // Host aliases for DNS override (needed for Talos to resolve cnoe.localtest.me)
  // Maps hostnames to the ingress-nginx ClusterIP
  hostAliases?: Array<{
    ip: string;
    hostnames: string[];
  }>;
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
    const backstageImage = props.image ?? 'docker.io/vpittamp23/backstage:1.1.0';
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
    // ConfigMap: app-config-overlay (for proxy target overrides)
    // Only created when proxyConfig is specified
    // ==========================================================================

    const hasProxyConfig = !!props.proxyConfig;

    if (hasProxyConfig) {
      const proxyPort = props.proxyConfig!.port ?? 8443;
      const proxyScheme = props.proxyConfig!.https !== false ? 'https' : 'http';
      const proxyBaseUrl = `${proxyScheme}://${props.proxyConfig!.baseHost}:${proxyPort}`;

      // Create app-config overlay that overrides proxy targets
      // This uses Backstage's config merging - later config files override earlier ones
      const appConfigOverlay = `
# Backstage app-config overlay for proxy target overrides
# This file is auto-generated by BackstageChart
# It overrides the default cnoe.localtest.me proxy targets with cluster-specific URLs

proxy:
  endpoints:
    '/agent-forge':
      target: ${proxyBaseUrl}
      pathRewrite:
        '^/api/proxy/agent-forge/?': '/'
      changeOrigin: true
      secure: false
    '/kargo':
      target: ${proxyBaseUrl}
      pathRewrite:
        '^/api/proxy/kargo/?': '/'
      changeOrigin: true
      secure: false

# Note: OIDC metadata URL is configured via KEYCLOAK_NAME_METADATA env var in backstage-env-vars secret
`;

      new k8s.KubeConfigMap(this, 'backstage-app-config-overlay', {
        metadata: {
          name: 'backstage-app-config-overlay',
          namespace,
          annotations: {
            'argocd.argoproj.io/sync-wave': '15', // After secrets, before deployment
          },
        },
        data: {
          'app-config.overlay.yaml': appConfigOverlay,
        },
      });
    }

    // ==========================================================================
    // Deployment: Backstage (sync-wave: 20)
    // ==========================================================================

    // Build volumes list - conditionally include config overlay
    const volumes: k8s.Volume[] = hasProxyConfig ? [
      {
        name: 'app-config-overlay',
        configMap: {
          name: 'backstage-app-config-overlay',
        },
      },
    ] : [];

    // Build volume mounts - conditionally include config overlay mount
    const volumeMounts: k8s.VolumeMount[] = hasProxyConfig ? [
      {
        name: 'app-config-overlay',
        mountPath: '/app/config',
        readOnly: true,
      },
    ] : [];

    // Build additional env vars for config overlay
    // Backstage reads APP_CONFIG_app_config_<name>=/path/to/file to load additional config
    const configEnvVars: k8s.EnvVar[] = hasProxyConfig ? [
      {
        name: 'APP_CONFIG_app_config_overlay',
        value: '/app/config/app-config.overlay.yaml',
      },
    ] : [];

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
                  ...configEnvVars,
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
                ...(volumeMounts.length > 0 && { volumeMounts }),
              },
            ],
            ...(volumes.length > 0 && { volumes }),
          },
        },
      },
    });

    // ==========================================================================
    // Ingress
    // ==========================================================================

    // Build ingress annotations
    const ingressAnnotations: Record<string, string> = {};
    if (props.tls?.clusterIssuer) {
      ingressAnnotations['cert-manager.io/cluster-issuer'] = props.tls.clusterIssuer;
    }

    // Build TLS configuration if enabled
    const tlsConfig = props.tls?.enabled ? [{
      hosts: ingressHosts,
      secretName: props.tls.secretName ?? `${appName}-tls`,
    }] : undefined;

    new k8s.KubeIngress(this, 'backstage-ingress', {
      metadata: {
        name: appName,
        namespace,
        ...(Object.keys(ingressAnnotations).length > 0 && { annotations: ingressAnnotations }),
      },
      spec: {
        ingressClassName: 'nginx',
        ...(tlsConfig && { tls: tlsConfig }),
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
