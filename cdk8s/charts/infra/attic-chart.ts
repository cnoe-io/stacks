import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface AtticChartProps extends ChartProps {
  minioEndpoint?: string;
  bucketName?: string;
  minioCredentialsSecret?: string;
  resources?: {
    requests?: { memory?: string; cpu?: string };
    limits?: { memory?: string; cpu?: string };
  };
}

export class AtticChart extends Chart {
  constructor(scope: Construct, id: string, props?: AtticChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'nix-cache';
    const minioEndpoint = props?.minioEndpoint || 'http://minio.nix-cache.svc.cluster.local:9000';
    const bucketName = props?.bucketName || 'attic-cache';
    const minioCredentialsSecret = props?.minioCredentialsSecret || 'minio-credentials';

    // Default resource configuration
    const resourceRequests = props?.resources?.requests || { memory: '256Mi', cpu: '250m' };
    const resourceLimits = props?.resources?.limits || { memory: '1Gi', cpu: '500m' };

    // T021-T026: ConfigMap with server.toml configuration
    const serverToml = `# Attic Server Configuration
# Listen address for HTTP API
[listen]
address = "[::]:8080"

# Database configuration (SQLite)
[database]
url = "sqlite:///var/lib/atticd/server.db?mode=rwc"

# S3 storage backend configuration
[storage]
type = "s3"
region = "us-east-1"
bucket = "${bucketName}"
endpoint = "${minioEndpoint}"

# Chunking configuration for content-addressed storage
[chunking]
nar-size-threshold = 65536      # 64 KiB - files smaller than this are not chunked
min-size = 16384                # 16 KiB - minimum chunk size
avg-size = 65536                # 64 KiB - target average chunk size
max-size = 262144               # 256 KiB - maximum chunk size

# Compression configuration
[compression]
type = "zstd"
level = 8                       # Compression level (1-22, higher = better compression)
`;

    new k8s.KubeConfigMap(this, 'configmap', {
      metadata: {
        name: 'attic-config',
        namespace,
        labels: {
          'app': 'attic',
          'app.kubernetes.io/name': 'attic',
          'app.kubernetes.io/component': 'nix-cache-server',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      data: {
        'server.toml': serverToml,
      },
    });

    // T027-T033: Attic Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'attic',
        namespace,
        labels: {
          'app': 'attic',
          'app.kubernetes.io/name': 'attic',
          'app.kubernetes.io/component': 'nix-cache-server',
          'app.kubernetes.io/part-of': 'nix-cache',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'attic',
          },
        },
        template: {
          metadata: {
            labels: {
              'app': 'attic',
              'app.kubernetes.io/name': 'attic',
              'app.kubernetes.io/component': 'nix-cache-server',
            },
          },
          spec: {
            // T031: Security context - root required for SQLite file permissions
            // Justification: SQLite database requires write access to /var/lib/atticd
            // See plan.md Section VII for security exception documentation
            securityContext: {
              runAsUser: 0,
              runAsGroup: 0,
              fsGroup: 0,
            },
            containers: [
              {
                name: 'attic',
                image: 'ghcr.io/zhaofengli/attic:latest',
                command: ['atticd'],
                args: ['-f', '/etc/atticd/server.toml'],
                ports: [
                  {
                    containerPort: 8080,
                    name: 'http',
                    protocol: 'TCP',
                  },
                ],
                // T028: Environment variables from MinIO Secret
                env: [
                  {
                    name: 'AWS_ACCESS_KEY_ID',
                    valueFrom: {
                      secretKeyRef: {
                        name: minioCredentialsSecret,
                        key: 'access-key',
                      },
                    },
                  },
                  {
                    name: 'AWS_SECRET_ACCESS_KEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: minioCredentialsSecret,
                        key: 'secret-key',
                      },
                    },
                  },
                ],
                // T029: Volume mounts
                volumeMounts: [
                  {
                    name: 'config',
                    mountPath: '/etc/atticd',
                    readOnly: true,
                  },
                  {
                    name: 'data',
                    mountPath: '/var/lib/atticd',
                  },
                ],
                // T030: Resource limits
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString(resourceRequests.memory || '256Mi'),
                    cpu: k8s.Quantity.fromString(resourceRequests.cpu || '250m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString(resourceLimits.memory || '1Gi'),
                    cpu: k8s.Quantity.fromString(resourceLimits.cpu || '500m'),
                  },
                },
                // T032: Readiness probe
                readinessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(8080),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                },
                // T033: Liveness probe
                livenessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(8080),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                },
              },
            ],
            volumes: [
              {
                name: 'config',
                configMap: {
                  name: 'attic-config',
                },
              },
              {
                name: 'data',
                emptyDir: {},
              },
            ],
          },
        },
      },
    });

    // T034: Attic Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'attic',
        namespace,
        labels: {
          'app': 'attic',
          'app.kubernetes.io/name': 'attic',
          'app.kubernetes.io/component': 'nix-cache-server',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: {
          'app': 'attic',
        },
        ports: [
          {
            name: 'http',
            port: 8080,
            targetPort: k8s.IntOrString.fromNumber(8080),
            protocol: 'TCP',
          },
        ],
      },
    });
  }
}
