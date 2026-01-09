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

export interface BackstageAgentForgeConfig {
  // Enable agentForge plugin configuration
  enabled: boolean;
  // Bot name displayed in UI (default: 'CAIPE')
  botName?: string;
  // Header title (default: 'CAIPE')
  headerTitle?: string;
  // Header subtitle (default: 'AI Platform Engineer Assistant')
  headerSubtitle?: string;
  // Input placeholder text (default: 'Ask CAIPE anything...')
  inputPlaceholder?: string;
}

export interface BackstageExternalAccessConfig {
  // Enable service-to-service authentication via static token
  enabled: boolean;
  // Subject identifier for the token (default: 'caipe-api-access')
  subject?: string;
  // Secret name containing the token (default: 'backstage-api-token')
  tokenSecretName?: string;
  // Secret key containing the token (default: 'token')
  tokenSecretKey?: string;
}

export interface BackstageChartProps extends ChartProps {
  // Namespace for Backstage (default: backstage)
  namespace?: string;
  // Backstage image (default: docker.io/vpittamp23/backstage:1.1.0)
  image?: string;
  // Image pull secret name (default: ghcr-dockercfg). Set to null to omit.
  imagePullSecretName?: string | null;
  // PostgreSQL image (default: docker.io/library/postgres:15.3-alpine3.18)
  postgresImage?: string;
  // PostgreSQL storage size (default: 500Mi)
  postgresStorageSize?: string;
  // Ingress hosts (default: ['localhost', 'cnoe.localtest.me'])
  ingressHosts?: string[];
  // Base path for hosting Backstage behind an ingress (default: '/backstage')
  // Note: Backstage is configured (via BACKSTAGE_FRONTEND_URL) to expect '/backstage' by default.
  // This chart configures the ingress to rewrite '/backstage/*' -> '/*' for the service.
  basePath?: string;
  // Redirect requests to '/' -> basePath (default: true)
  redirectRootToBasePath?: boolean;
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
  // agentForge plugin configuration for CAIPE integration
  agentForgeConfig?: BackstageAgentForgeConfig;
  // External access configuration for service-to-service auth (CAIPE agents)
  // When enabled, configures backend.auth.externalAccess with a static token
  externalAccessConfig?: BackstageExternalAccessConfig;
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
    const imagePullSecretName = props.imagePullSecretName ?? 'ghcr-dockercfg';
    const postgresImage = props.postgresImage ?? 'docker.io/library/postgres:15.3-alpine3.18';
    const postgresStorageSize = props.postgresStorageSize ?? '500Mi';
    const ingressHosts = props.ingressHosts ?? ['localhost', 'cnoe.localtest.me'];
    const basePathRaw = props.basePath ?? '/backstage';
    const basePath = basePathRaw.startsWith('/') ? basePathRaw : `/${basePathRaw}`;
    const basePathNoTrailingSlash = basePath.length > 1 && basePath.endsWith('/') ? basePath.slice(0, -1) : basePath;
    const redirectRootToBasePath = props.redirectRootToBasePath ?? true;

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

    // ClusterRole: {namespace}-argo-worfklows (namespace-prefixed for multi-deployment isolation)
    // Note: typo "worfklows" maintained for ref-implementation compatibility
    new k8s.KubeClusterRole(this, 'backstage-argo-workflows-cr', {
      metadata: {
        name: `${namespace}-argo-worfklows`,
      },
      rules: [
        {
          apiGroups: ['argoproj.io'],
          resources: ['workflows'],
          verbs: ['create'],
        },
      ],
    });

    // ClusterRole: {namespace}-read-all (namespace-prefixed for multi-deployment isolation)
    new k8s.KubeClusterRole(this, 'backstage-read-all-cr', {
      metadata: {
        name: `${namespace}-read-all`,
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

    // ClusterRoleBinding: {namespace}-argo-worfklows (namespace-prefixed for multi-deployment isolation)
    new k8s.KubeClusterRoleBinding(this, 'backstage-argo-workflows-crb', {
      metadata: {
        name: `${namespace}-argo-worfklows`,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: `${namespace}-argo-worfklows`,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: appName,
          namespace,
        },
      ],
    });

    // ClusterRoleBinding: {namespace}-read-all (namespace-prefixed for multi-deployment isolation)
    new k8s.KubeClusterRoleBinding(this, 'backstage-read-all-crb', {
      metadata: {
        name: `${namespace}-read-all`,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: `${namespace}-read-all`,
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
    // ConfigMap: app-config-overlay (for proxy target, agentForge, and externalAccess overrides)
    // Created when proxyConfig, agentForgeConfig, or externalAccessConfig is specified
    // ==========================================================================

    const hasProxyConfig = !!props.proxyConfig;
    const hasAgentForgeConfig = !!props.agentForgeConfig?.enabled;
    const hasExternalAccessConfig = !!props.externalAccessConfig?.enabled;
    const hasAnyConfig = hasProxyConfig || hasAgentForgeConfig || hasExternalAccessConfig;

    if (hasAnyConfig) {
      // Build proxy section if proxyConfig specified
      let proxySection = '';
      if (hasProxyConfig) {
        const proxyPort = props.proxyConfig!.port ?? 8443;
        const proxyScheme = props.proxyConfig!.https !== false ? 'https' : 'http';
        const proxyBaseUrl = `${proxyScheme}://${props.proxyConfig!.baseHost}:${proxyPort}`;

        proxySection = `
proxy:
  endpoints:
    '/agent-forge':
      target: ${proxyBaseUrl}
      pathRewrite:
        '^/api/proxy/agent-forge/?': '/'
      changeOrigin: true
      secure: false
`;
      }

      // Build agentForge section if agentForgeConfig specified
      let agentForgeSection = '';
      if (hasAgentForgeConfig) {
        const botName = props.agentForgeConfig!.botName ?? 'CAIPE';
        const headerTitle = props.agentForgeConfig!.headerTitle ?? 'CAIPE';
        const headerSubtitle = props.agentForgeConfig!.headerSubtitle ?? 'AI Platform Engineer Assistant';
        const inputPlaceholder = props.agentForgeConfig!.inputPlaceholder ?? 'Ask CAIPE anything...';

        agentForgeSection = `
agentForge:
  baseUrl: \${AGENT_FORGE_URL}
  botName: ${botName}
  infoPage: https://cnoe-io.github.io/ai-platform-engineering/
  showOptions: true
  useOpenIDToken: true
  enableStreaming: false
  requestTimeout: 300
  headerTitle: ${headerTitle}
  headerSubtitle: ${headerSubtitle}
  inputPlaceholder: ${inputPlaceholder}
  initialSuggestions:
    - Create GitHub Repository
    - Deploy ArgoCD Application
    - Get LLM keys
  thinkingMessagesInterval: 7000
  thinkingMessages:
    - "Processing query - even great thoughts start with a single thread."
    - "Contacting agents - because collaboration beats computation."
    - "Analyzing data - the truth hides between the averages."
    - "Reflecting on the prompt - clarity is the best optimization."
    - "Syncing thoughts across nodes - wisdom prefers low latency."
    - "Assembling context - the art of not missing the missing piece."
`;
      }

      // Build externalAccess section if externalAccessConfig specified
      // This enables service-to-service authentication for CAIPE agents
      // See: https://backstage.io/docs/auth/service-to-service-auth/
      let externalAccessSection = '';
      if (hasExternalAccessConfig) {
        const subject = props.externalAccessConfig!.subject ?? 'caipe-api-access';
        const tokenSecretName = props.externalAccessConfig!.tokenSecretName ?? 'backstage-api-token';
        const tokenSecretKey = props.externalAccessConfig!.tokenSecretKey ?? 'token';

        // The token is read from a K8s secret and mounted as an env var
        // We use BACKSTAGE_API_TOKEN env var which will be set via envFrom
        externalAccessSection = `
backend:
  auth:
    externalAccess:
      - type: static
        options:
          token: \${BACKSTAGE_API_TOKEN}
          subject: ${subject}
`;
      }

      // Database pool configuration to prevent migration lock race conditions
      // See: https://github.com/backstage/backstage/issues/27186
      // See: https://github.com/backstage/backstage/issues/24284
      // Increase pool size and timeouts to handle concurrent plugin initialization
      // Note: If externalAccess is enabled, we merge it under the backend key
      const databaseSection = hasExternalAccessConfig ? `  database:
    knexConfig:
      pool:
        min: 2
        max: 30
        acquireTimeoutMillis: 60000
        idleTimeoutMillis: 60000
        createTimeoutMillis: 30000
` : `
backend:
  database:
    knexConfig:
      pool:
        min: 2
        max: 30
        acquireTimeoutMillis: 60000
        idleTimeoutMillis: 60000
        createTimeoutMillis: 30000
`;

      // Create app-config overlay that combines all sections
      // This uses Backstage's config merging - later config files override earlier ones
      const appConfigOverlay = `# Backstage app-config overlay
# This file is auto-generated by BackstageChart
# It provides cluster-specific configuration overrides
${externalAccessSection}${databaseSection}${proxySection}${agentForgeSection}
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
    const volumes: k8s.Volume[] = hasAnyConfig ? [
      {
        name: 'app-config-overlay',
        configMap: {
          name: 'backstage-app-config-overlay',
        },
      },
    ] : [];

    // Build volume mounts - conditionally include config overlay mount
    const volumeMounts: k8s.VolumeMount[] = hasAnyConfig ? [
      {
        name: 'app-config-overlay',
        mountPath: '/app/config',
        readOnly: true,
      },
    ] : [];

    // Build additional env vars for config overlay
    // Backstage reads APP_CONFIG_app_config_<name>=/path/to/file to load additional config
    const configEnvVars: k8s.EnvVar[] = hasAnyConfig ? [
      {
        name: 'APP_CONFIG_app_config_overlay',
        value: '/app/config/app-config.overlay.yaml',
      },
    ] : [];

    // Build envFrom list - conditionally include token secret for externalAccess
    const tokenSecretName = props.externalAccessConfig?.tokenSecretName ?? 'backstage-api-token';
    const baseEnvFrom: k8s.EnvFromSource[] = [
      { secretRef: { name: 'backstage-env-vars' } },
      { secretRef: { name: 'gitea-credentials' } },
      { secretRef: { name: 'argocd-credentials' } },
    ];
    const envFromSources: k8s.EnvFromSource[] = hasExternalAccessConfig
      ? [...baseEnvFrom, { secretRef: { name: tokenSecretName } }]
      : baseEnvFrom;

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
        strategy: {
          type: 'Recreate',
        },
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
            ...(imagePullSecretName && {
              imagePullSecrets: [
                {
                  name: imagePullSecretName,
                },
              ],
            }),
            // Run as root to allow env config injection into static files
            securityContext: {
              runAsUser: 0,
              runAsGroup: 0,
              fsGroup: 0,
            },
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
                envFrom: envFromSources,
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

    // Backstage is configured to expect a basePath (default '/backstage').
    // Rewrite '/backstage/*' -> '/*' so the service can run on root paths.
    const backstageIngressPath = basePathNoTrailingSlash === '/'
      ? '/'
      : `${basePathNoTrailingSlash}(/|$)(.*)`;
    const backstageIngressPathType = basePathNoTrailingSlash === '/'
      ? 'Prefix'
      : 'ImplementationSpecific';

    if (basePathNoTrailingSlash !== '/') {
      ingressAnnotations['nginx.ingress.kubernetes.io/use-regex'] = 'true';
      ingressAnnotations['nginx.ingress.kubernetes.io/rewrite-target'] = '/$2';
    }

    // Build TLS configuration if enabled
    const tlsConfig = props.tls?.enabled ? [{
      hosts: ingressHosts,
      secretName: props.tls.secretName ?? `${appName}-tls`,
    }] : undefined;

    // Optional root redirect: '/' -> '/backstage'
    // This avoids a blank page when Backstage is configured with a non-root baseUrl.
    if (redirectRootToBasePath && basePathNoTrailingSlash !== '/') {
      new k8s.KubeIngress(this, 'backstage-root-redirect-ingress', {
        metadata: {
          name: `${appName}-root-redirect`,
          namespace,
          annotations: {
            'nginx.ingress.kubernetes.io/use-regex': 'true',
            'nginx.ingress.kubernetes.io/permanent-redirect': basePathNoTrailingSlash,
          },
        },
        spec: {
          ingressClassName: 'nginx',
          ...(tlsConfig && { tls: tlsConfig }),
          rules: ingressHosts.map(host => ({
            host,
            http: {
              paths: [
                {
                  // Match only the root path
                  path: '/$',
                  pathType: 'ImplementationSpecific',
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
                path: backstageIngressPath,
                pathType: backstageIngressPathType,
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
