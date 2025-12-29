/**
 * FliptChart - Flipt feature flag management deployment
 *
 * Deploys Flipt as the feature flag management UI and storage backend.
 * - HTTP UI and API (8080) for flag management
 * - gRPC endpoint (9000) for flagd sync
 * - Git backend for GitOps flag storage
 * - OIDC authentication via Keycloak
 *
 * Sync wave: -75 (after secrets, before applications)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { getClusterSuffix } from '../../lib/cluster-identity';

export interface FliptChartProps extends ChartProps {
  /**
   * Namespace for Flipt deployment
   * @default 'feature-flags'
   */
  namespace?: string;

  /**
   * Flipt image version
   * @default '1.56.0'
   */
  imageVersion?: string;

  /**
   * Ingress host for Flipt UI
   * @default 'flipt-<cluster>.<INGRESS_HOST>'
   */
  ingressHost?: string;

  /**
   * Git repository URL for flag storage
   * @default 'https://gitea.cnoe.localtest.me:8443/giteaAdmin/feature-flags.git'
   */
  gitRepositoryUrl?: string;

  /**
   * Git repository branch
   * @default 'main'
   */
  gitBranch?: string;

  /**
   * Git poll interval for sync
   * @default '30s'
   */
  gitPollInterval?: string;

  /**
   * CPU request
   * @default '100m'
   */
  cpuRequest?: string;

  /**
   * CPU limit
   * @default '500m'
   */
  cpuLimit?: string;

  /**
   * Memory request
   * @default '128Mi'
   */
  memoryRequest?: string;

  /**
   * Memory limit
   * @default '256Mi'
   */
  memoryLimit?: string;
}

export class FliptChart extends Chart {
  constructor(scope: Construct, id: string, props?: FliptChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'feature-flags';
    const imageVersion = props?.imageVersion || '1.56.0';
    const baseHost = process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const isKind = baseHost === 'cnoe.localtest.me';
    const portSuffix = isKind ? ':8443' : '';
    const ingressHost = props?.ingressHost || `flipt${getClusterSuffix()}.${baseHost}`;

    // Git repository URL
    const giteaHost = isKind ? `gitea.${baseHost}${portSuffix}` : `gitea.${baseHost}`;
    const gitRepositoryUrl = props?.gitRepositoryUrl || `https://${giteaHost}/giteaAdmin/feature-flags.git`;
    const gitBranch = props?.gitBranch || 'main';
    const gitPollInterval = props?.gitPollInterval || '30s';

    const cpuRequest = props?.cpuRequest || '100m';
    const cpuLimit = props?.cpuLimit || '500m';
    const memoryRequest = props?.memoryRequest || '128Mi';
    const memoryLimit = props?.memoryLimit || '256Mi';

    const labels = {
      'app': 'flipt',
      'app.kubernetes.io/name': 'flipt',
      'app.kubernetes.io/component': 'management-ui',
      'app.kubernetes.io/part-of': 'feature-flags',
    };

    const syncWave = '-75';

    // ConfigMap for Flipt configuration
    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'flipt-config',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      data: {
        'flipt.yml': `# Flipt configuration
# https://docs.flipt.io/configuration/overview

log:
  level: info
  encoding: json

server:
  protocol: http
  http_port: 8080
  grpc_port: 9000

storage:
  type: git
  git:
    repository: "${gitRepositoryUrl}"
    ref: "${gitBranch}"
    poll_interval: "${gitPollInterval}"
    # Authentication is provided via environment variables:
    # FLIPT_STORAGE_GIT_AUTHENTICATION_BASIC_USERNAME
    # FLIPT_STORAGE_GIT_AUTHENTICATION_BASIC_PASSWORD
    insecure_skip_tls_verify: true

# Authentication configuration
# OIDC credentials provided via environment variables from secrets
authentication:
  required: true
  session:
    domain: "${ingressHost}"
    secure: true
  methods:
    token:
      enabled: false
    oidc:
      enabled: true
      cleanup:
        interval: "10m"
        grace_period: "30m"

# Audit logging
audit:
  sinks:
    log:
      enabled: true

# Telemetry
telemetry:
  enabled: true
`,
      },
    });

    // PersistentVolumeClaim for Flipt data (local cache)
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'flipt-data',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString('1Gi'),
          },
        },
      },
    });

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'flipt',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'flipt',
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
                name: 'flipt',
                image: `ghcr.io/flipt-io/flipt:v${imageVersion}`,
                command: ['/flipt'],
                args: [
                  '--config', '/etc/flipt/flipt.yml',
                ],
                ports: [
                  { containerPort: 8080, name: 'http', protocol: 'TCP' },
                  { containerPort: 9000, name: 'grpc', protocol: 'TCP' },
                ],
                envFrom: [
                  // OIDC credentials from secret
                  { secretRef: { name: 'flipt-oidc' } },
                  // Git credentials from secret
                  { secretRef: { name: 'flipt-git-credentials' } },
                ],
                env: [
                  // Additional environment variables
                  { name: 'FLIPT_LOG_LEVEL', value: 'info' },
                  // Use idpbuilder CA for TLS verification
                  { name: 'GIT_SSL_CAINFO', value: '/etc/ssl/certs/idpbuilder-ca.crt' },
                  { name: 'SSL_CERT_FILE', value: '/etc/ssl/certs/idpbuilder-ca.crt' },
                ],
                volumeMounts: [
                  {
                    name: 'config',
                    mountPath: '/etc/flipt',
                    readOnly: true,
                  },
                  {
                    name: 'data',
                    mountPath: '/var/opt/flipt',
                  },
                  {
                    name: 'idpbuilder-ca',
                    mountPath: '/etc/ssl/certs/idpbuilder-ca.crt',
                    subPath: 'ca.crt',
                    readOnly: true,
                  },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString(cpuRequest),
                    memory: k8s.Quantity.fromString(memoryRequest),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString(cpuLimit),
                    memory: k8s.Quantity.fromString(memoryLimit),
                  },
                },
                securityContext: {
                  allowPrivilegeEscalation: false,
                  capabilities: {
                    drop: ['ALL'],
                  },
                },
                livenessProbe: {
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(8080),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                  failureThreshold: 3,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(8080),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                  failureThreshold: 3,
                },
              },
            ],
            volumes: [
              {
                name: 'config',
                configMap: {
                  name: 'flipt-config',
                },
              },
              {
                name: 'data',
                persistentVolumeClaim: {
                  claimName: 'flipt-data',
                },
              },
              {
                name: 'idpbuilder-ca',
                secret: {
                  secretName: 'idpbuilder-cert',
                },
              },
            ],
          },
        },
      },
    });

    // Service for HTTP and gRPC
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'flipt',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'flipt' },
        ports: [
          {
            name: 'http',
            port: 8080,
            targetPort: k8s.IntOrString.fromNumber(8080),
            protocol: 'TCP',
          },
          {
            name: 'grpc',
            port: 9000,
            targetPort: k8s.IntOrString.fromNumber(9000),
            protocol: 'TCP',
          },
        ],
      },
    });

    // Ingress for UI access
    new k8s.KubeIngress(this, 'ingress', {
      metadata: {
        name: 'flipt',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
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
                      name: 'flipt',
                      port: {
                        number: 8080,
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
