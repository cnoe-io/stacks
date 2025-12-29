/**
 * KeycloakChart - Identity Provider for SSO/OIDC
 *
 * This chart deploys Keycloak with PostgreSQL backend.
 * Based on ref-implementation/keycloak but as a proper CDK8s chart
 * with cluster-type awareness for Kind vs Talos deployments.
 *
 * Constitution Alignment:
 * - Principle I (CDK8s Typed Composition): Uses typed k8s imports
 * - Principle V (External Secrets Management): Uses ESO for credentials
 * - Principle IX (Unified Bootstrap): Cluster-type aware configuration
 */

import { Construct } from 'constructs';
import { Chart, ChartProps } from 'cdk8s';
import * as k8s from '../../imports/k8s';

export interface KeycloakChartProps extends ChartProps {
  /**
   * Namespace for Keycloak (default: keycloak)
   */
  namespace?: string;

  /**
   * Base hostname for Keycloak (default: cnoe.localtest.me)
   * For Kind: cnoe.localtest.me
   * For Talos: ai401kchat.com
   */
  hostname?: string;

  /**
   * Port for hostname (default: 8443 for Kind, 443 for Talos)
   */
  hostnamePort?: number;

  /**
   * HTTP relative path (default: /keycloak)
   */
  httpRelativePath?: string;

  /**
   * Keycloak image (default: quay.io/keycloak/keycloak:22.0.3)
   */
  image?: string;

  /**
   * PostgreSQL image (default: docker.io/library/postgres:15.3-alpine3.18)
   */
  postgresImage?: string;

  /**
   * PostgreSQL storage size (default: 500Mi)
   */
  postgresStorageSize?: string;

  /**
   * TLS configuration for ingress
   */
  tls?: {
    enabled: boolean;
    secretName?: string;
    clusterIssuer?: string;
  };

  /**
   * Ingress hosts (default: ['localhost', 'cnoe.localtest.me'])
   */
  ingressHosts?: string[];

  /**
   * Enable declarative realm import from ConfigMap
   * When enabled, mounts keycloak-realm-import ConfigMap and imports on startup
   * @default true
   */
  enableRealmImport?: boolean;

  /**
   * Secret name containing client secrets for realm import
   * These are injected as environment variables for ${env.VAR} substitution
   * @default 'keycloak-client-secrets'
   */
  clientSecretsSecretName?: string;
}

/**
 * KeycloakChart - Deploys Keycloak identity provider with PostgreSQL
 *
 * Creates resources:
 * 1. Namespace: keycloak
 * 2. Service: keycloak (ClusterIP, port 8080)
 * 3. Service: postgresql (headless, port 5432)
 * 4. ConfigMap: keycloak-config (keycloak.conf)
 * 5. StatefulSet: postgresql (sync-wave 0)
 * 6. Deployment: keycloak (sync-wave 10)
 * 7. Ingress: keycloak-ingress (sync-wave 100)
 *
 * Note: Secrets (keycloak-config with credentials) are created by KeycloakSecretsChart
 */
export class KeycloakChart extends Chart {
  constructor(scope: Construct, id: string, props: KeycloakChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace ?? 'keycloak';
    const hostname = props.hostname ?? 'cnoe.localtest.me';
    const hostnamePort = props.hostnamePort ?? 8443;
    const httpRelativePath = props.httpRelativePath ?? '/keycloak';
    const keycloakImage = props.image ?? 'quay.io/keycloak/keycloak:22.0.3';
    const postgresImage = props.postgresImage ?? 'docker.io/library/postgres:15.3-alpine3.18';
    const postgresStorageSize = props.postgresStorageSize ?? '500Mi';
    const ingressHosts = props.ingressHosts ?? ['localhost', hostname];
    const enableRealmImport = props.enableRealmImport ?? true;
    const clientSecretsSecretName = props.clientSecretsSecretName ?? 'keycloak-client-secrets';

    // ==========================================================================
    // Namespace
    // ==========================================================================

    new k8s.KubeNamespace(this, 'keycloak-namespace', {
      metadata: {
        name: namespace,
        labels: {
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // ==========================================================================
    // Services
    // ==========================================================================

    // Keycloak Service
    new k8s.KubeService(this, 'keycloak-service', {
      metadata: {
        name: 'keycloak',
        namespace,
        labels: {
          app: 'keycloak',
        },
      },
      spec: {
        ports: [
          {
            name: 'http',
            port: 8080,
            targetPort: k8s.IntOrString.fromNumber(8080),
          },
        ],
        selector: {
          app: 'keycloak',
        },
        type: 'ClusterIP',
      },
    });

    // PostgreSQL Headless Service
    new k8s.KubeService(this, 'postgresql-service', {
      metadata: {
        name: 'postgresql',
        namespace,
        labels: {
          app: 'postgresql',
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
          app: 'postgresql',
        },
      },
    });

    // ==========================================================================
    // ConfigMap
    // ==========================================================================

    // Build hostname admin URL
    const hostnameAdmin = hostnamePort === 443 ? hostname : `${hostname}:${hostnamePort}`;

    new k8s.KubeConfigMap(this, 'keycloak-config-cm', {
      metadata: {
        name: 'keycloak-config',
        namespace,
      },
      data: {
        'keycloak.conf': `# Database
# The database vendor.
db=postgres

# The username of the database user.
db-url=jdbc:postgresql://postgresql.${namespace}.svc.cluster.local:5432/postgres

# The proxy address forwarding mode if the server is behind a reverse proxy.
proxy=edge

# hostname configuration
hostname=${hostname}
hostname-port=${hostnamePort}
http-relative-path=${httpRelativePath}

# the admin url requires its own configuration to reflect correct url
hostname-admin=${hostnameAdmin}

hostname-debug=true

# this should only be allowed in development. NEVER in production.
hostname-strict=false
hostname-strict-backchannel=false
`,
      },
    });

    // ==========================================================================
    // StatefulSet: PostgreSQL (sync-wave: 0)
    // ==========================================================================

    new k8s.KubeStatefulSet(this, 'postgresql-statefulset', {
      metadata: {
        name: 'postgresql',
        namespace,
        labels: {
          app: 'postgresql',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '0',
        },
      },
      spec: {
        replicas: 1,
        serviceName: 'service-postgresql',
        selector: {
          matchLabels: {
            app: 'postgresql',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'postgresql',
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
                envFrom: [
                  {
                    secretRef: {
                      name: 'keycloak-config',
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
    // Deployment: Keycloak (sync-wave: 10)
    // ==========================================================================

    // Build container args based on realm import setting
    const keycloakArgs = enableRealmImport
      ? ['start-dev', '--import-realm']
      : ['start-dev'];

    // Build envFrom array - always include keycloak-config, optionally add client secrets
    const envFromRefs: k8s.EnvFromSource[] = [
      {
        secretRef: {
          name: 'keycloak-config',
        },
      },
    ];
    if (enableRealmImport) {
      envFromRefs.push({
        secretRef: {
          name: clientSecretsSecretName,
          optional: true, // Optional to allow graceful degradation if secret doesn't exist yet
        },
      });
    }

    // Build volume mounts - always include config, optionally add realm import
    const volumeMounts: k8s.VolumeMount[] = [
      {
        name: 'keycloak-config',
        mountPath: '/opt/keycloak/conf',
        readOnly: true,
      },
    ];
    if (enableRealmImport) {
      volumeMounts.push({
        name: 'realm-import',
        mountPath: '/opt/keycloak/data/import',
        readOnly: true,
      });
    }

    // Build volumes - always include config, optionally add realm import
    const volumes: k8s.Volume[] = [
      {
        name: 'keycloak-config',
        configMap: {
          name: 'keycloak-config',
        },
      },
    ];
    if (enableRealmImport) {
      // Template volume from ConfigMap (read by init container)
      volumes.push({
        name: 'realm-import-template',
        configMap: {
          name: 'keycloak-realm-import',
        },
      });
      // Processed volume (written by init container, read by Keycloak)
      volumes.push({
        name: 'realm-import',
        emptyDir: {},
      });
    }

    // Init containers for realm import (envsubst to substitute secrets)
    const initContainers: k8s.Container[] = [];
    if (enableRealmImport) {
      initContainers.push({
        name: 'realm-import-envsubst',
        image: 'docker.io/library/alpine:3.19',
        command: ['/bin/sh', '-c'],
        args: [
          // Install gettext for envsubst, then process the realm JSON
          `apk add --no-cache gettext && \
           envsubst < /realm-template/cnoe-realm.json > /realm-import/cnoe-realm.json && \
           echo "Realm import file processed successfully"`,
        ],
        envFrom: [
          {
            secretRef: {
              name: clientSecretsSecretName,
              optional: true,
            },
          },
          {
            secretRef: {
              name: 'keycloak-config',
            },
          },
        ],
        volumeMounts: [
          {
            name: 'realm-import-template',
            mountPath: '/realm-template',
            readOnly: true,
          },
          {
            name: 'realm-import',
            mountPath: '/realm-import',
          },
        ],
      });
    }

    new k8s.KubeDeployment(this, 'keycloak-deployment', {
      metadata: {
        name: 'keycloak',
        namespace,
        labels: {
          app: 'keycloak',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '10',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'keycloak',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'keycloak',
            },
          },
          spec: {
            ...(initContainers.length > 0 && { initContainers }),
            containers: [
              {
                name: 'keycloak',
                image: keycloakImage,
                args: keycloakArgs,
                env: [
                  {
                    name: 'KEYCLOAK_ADMIN',
                    value: 'cnoe-admin',
                  },
                  {
                    name: 'KEYCLOAK_LOGLEVEL',
                    value: 'ALL',
                  },
                  {
                    name: 'QUARKUS_TRANSACTION_MANAGER_ENABLE_RECOVERY',
                    value: 'true',
                  },
                ],
                envFrom: envFromRefs,
                ports: [
                  {
                    containerPort: 8080,
                    name: 'http',
                  },
                ],
                readinessProbe: {
                  httpGet: {
                    path: `${httpRelativePath}/realms/master`,
                    port: k8s.IntOrString.fromNumber(8080),
                  },
                },
                volumeMounts: volumeMounts,
              },
            ],
            volumes: volumes,
          },
        },
      },
    });

    // ==========================================================================
    // Ingress (sync-wave: 100)
    // ==========================================================================

    // Build ingress annotations
    const ingressAnnotations: Record<string, string> = {
      'argocd.argoproj.io/sync-wave': '100',
    };
    if (props.tls?.clusterIssuer) {
      ingressAnnotations['cert-manager.io/cluster-issuer'] = props.tls.clusterIssuer;
    }

    // Build TLS configuration if enabled
    const tlsConfig = props.tls?.enabled
      ? [
          {
            hosts: ingressHosts,
            secretName: props.tls.secretName ?? 'keycloak-tls',
          },
        ]
      : undefined;

    new k8s.KubeIngress(this, 'keycloak-ingress', {
      metadata: {
        name: 'keycloak-ingress',
        namespace,
        annotations: ingressAnnotations,
      },
      spec: {
        ingressClassName: 'nginx',
        ...(tlsConfig && { tls: tlsConfig }),
        rules: ingressHosts.map((host) => ({
          host,
          http: {
            paths: [
              {
                path: httpRelativePath,
                pathType: 'ImplementationSpecific',
                backend: {
                  service: {
                    name: 'keycloak',
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
