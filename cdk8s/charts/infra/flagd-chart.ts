/**
 * FlagdChart - OpenFeature flagd deployment
 *
 * Deploys flagd as a centralized feature flag evaluation service.
 * - gRPC endpoint (8013) for OpenFeature SDK evaluations
 * - OFREP HTTP endpoint (8016) for REST-based evaluations
 * - Metrics endpoint (8015) for Prometheus scraping
 * - Syncs with Flipt via gRPC for flag configurations
 *
 * Sync wave: -75 (after secrets, before applications)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface FlagdChartProps extends ChartProps {
  /**
   * Namespace for flagd deployment
   * @default 'feature-flags'
   */
  namespace?: string;

  /**
   * flagd image version
   * @default '0.11.0'
   */
  imageVersion?: string;

  /**
   * Flipt host for sync source
   * @default 'flipt.feature-flags.svc.cluster.local'
   */
  fliptHost?: string;

  /**
   * Flipt port for sync source
   * @default 8080
   */
  fliptPort?: number;

  /**
   * OpenTelemetry collector endpoint
   * @default 'otel-collector.observability.svc.cluster.local:4317'
   */
  otelCollectorEndpoint?: string;

  /**
   * CPU request
   * @default '50m'
   */
  cpuRequest?: string;

  /**
   * CPU limit
   * @default '200m'
   */
  cpuLimit?: string;

  /**
   * Memory request
   * @default '64Mi'
   */
  memoryRequest?: string;

  /**
   * Memory limit
   * @default '128Mi'
   */
  memoryLimit?: string;
}

export class FlagdChart extends Chart {
  constructor(scope: Construct, id: string, props?: FlagdChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'feature-flags';
    const imageVersion = props?.imageVersion || '0.11.0';
    const fliptHost = props?.fliptHost || 'flipt.feature-flags.svc.cluster.local';
    const fliptPort = props?.fliptPort || 8080;
    const otelCollectorEndpoint = props?.otelCollectorEndpoint || 'otel-collector.observability.svc.cluster.local:4317';

    const cpuRequest = props?.cpuRequest || '50m';
    const cpuLimit = props?.cpuLimit || '200m';
    const memoryRequest = props?.memoryRequest || '64Mi';
    const memoryLimit = props?.memoryLimit || '128Mi';

    const labels = {
      'app': 'flagd',
      'app.kubernetes.io/name': 'flagd',
      'app.kubernetes.io/component': 'evaluation-engine',
      'app.kubernetes.io/part-of': 'feature-flags',
    };

    const syncWave = '-75';

    // ConfigMap for flagd configuration
    // Includes CAIPE/Backstage feature flags (User Story 7)
    const flagConfig = {
      '$schema': 'https://flagd.dev/schema/v0/flags.json',
      'flags': {
        // ==========================================
        // Example flags (existing)
        // ==========================================
        'new-checkout-flow': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'off',
        },
        'dark-mode': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
        },

        // ==========================================
        // CAIPE Agent Control Flags (T067)
        // ==========================================
        'caipe-agents-enabled': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Master toggle for all CAIPE agent functionality',
            'owner': 'platform-team',
          },
        },
        'caipe-agent-argocd': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Enable ArgoCD agent for deployment operations',
            'owner': 'platform-team',
          },
        },
        'caipe-agent-github': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Enable GitHub agent for repository operations',
            'owner': 'platform-team',
          },
        },
        'caipe-agent-backstage': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Enable Backstage catalog agent',
            'owner': 'platform-team',
          },
        },

        // ==========================================
        // CAIPE Feature Flags (T068)
        // ==========================================
        'caipe-deep-orchestration': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'off',
          'metadata': {
            'description': 'Enable multi-agent deep orchestration mode',
            'owner': 'platform-team',
          },
          // Targeting: Enable for caipe-testers group
          'targeting': {
            'if': [
              {
                'in': ['caipe-testers', { 'var': 'groups' }],
              },
              'on',
              null,
            ],
          },
        },
        'caipe-artifact-streaming': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Enable streaming responses from agents',
            'owner': 'platform-team',
          },
        },

        // ==========================================
        // Observability Flags (T069)
        // ==========================================
        'langfuse-tracing-enabled': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Enable Langfuse LLM observability tracing',
            'owner': 'platform-team',
          },
        },
        'otel-trace-sampling-rate': {
          'state': 'ENABLED',
          'variants': {
            'full': 1.0,
            'half': 0.5,
            'tenth': 0.1,
            'off': 0.0,
          },
          'defaultVariant': 'full',
          'metadata': {
            'description': 'OpenTelemetry trace sampling rate (0.0 to 1.0)',
            'owner': 'platform-team',
          },
        },
        'verbose-agent-logging': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'off',
          'metadata': {
            'description': 'Enable verbose logging for CAIPE agents',
            'owner': 'platform-team',
          },
        },

        // ==========================================
        // Rate Limiting Flags (T070)
        // ==========================================
        'caipe-rate-limit': {
          'state': 'ENABLED',
          'variants': {
            'low': 20,
            'standard': 100,
            'high': 500,
            'unlimited': -1,
          },
          'defaultVariant': 'standard',
          'metadata': {
            'description': 'Requests per minute per user',
            'owner': 'platform-team',
          },
          // Targeting: Premium users get high rate limit
          'targeting': {
            'if': [
              { '==': [{ 'var': 'tier' }, 'premium'] },
              'high',
              null,
            ],
          },
        },
        'llm-token-limit': {
          'state': 'ENABLED',
          'variants': {
            'small': 1024,
            'standard': 4096,
            'large': 8192,
            'xlarge': 16384,
          },
          'defaultVariant': 'standard',
          'metadata': {
            'description': 'Maximum tokens per LLM request',
            'owner': 'platform-team',
          },
        },
        'agent-timeout-seconds': {
          'state': 'ENABLED',
          'variants': {
            'short': 30,
            'standard': 120,
            'long': 300,
            'extended': 600,
          },
          'defaultVariant': 'standard',
          'metadata': {
            'description': 'Agent request timeout in seconds',
            'owner': 'platform-team',
          },
        },

        // ==========================================
        // Backstage Flags (T071)
        // ==========================================
        'backstage-agentforge-enabled': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Show/hide AgentForge chat UI in Backstage',
            'owner': 'platform-team',
          },
        },
        'backstage-agentforge-suggestions': {
          'state': 'ENABLED',
          'variants': {
            'default': 'Create a repo,Deploy an app,Check status',
            'minimal': 'Help me',
            'advanced': 'Create a repo,Deploy an app,Check status,Run pipeline,Analyze logs',
          },
          'defaultVariant': 'default',
          'metadata': {
            'description': 'Suggestion chips shown in AgentForge chat',
            'owner': 'platform-team',
          },
        },
        'backstage-external-api-access': {
          'state': 'ENABLED',
          'variants': {
            'on': true,
            'off': false,
          },
          'defaultVariant': 'on',
          'metadata': {
            'description': 'Enable service-to-service API access for CAIPE agents',
            'owner': 'platform-team',
          },
        },
      },
    };

    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'flagd-config',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      data: {
        'flagd.json': JSON.stringify(flagConfig, null, 2),
      },
    });

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'flagd',
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
            'app': 'flagd',
          },
        },
        template: {
          metadata: {
            labels,
            annotations: {
              // Enable Prometheus scraping
              'prometheus.io/scrape': 'true',
              'prometheus.io/port': '8015',
              'prometheus.io/path': '/metrics',
            },
          },
          spec: {
            securityContext: {
              runAsNonRoot: true,
              runAsUser: 65532,
              runAsGroup: 65532,
              fsGroup: 65532,
            },
            containers: [
              {
                name: 'flagd',
                image: `ghcr.io/open-feature/flagd:v${imageVersion}`,
                args: [
                  'start',
                  // Use ConfigMap as flag source - Flipt is for management UI only
                  '--uri', 'file:/etc/flagd/flagd.json',
                  '--management-port', '8015',
                  '--port', '8013',
                  '--ofrep-port', '8016',
                ],
                ports: [
                  { containerPort: 8013, name: 'grpc', protocol: 'TCP' },
                  { containerPort: 8015, name: 'metrics', protocol: 'TCP' },
                  { containerPort: 8016, name: 'ofrep', protocol: 'TCP' },
                ],
                env: [
                  // OpenTelemetry configuration
                  { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: `http://${otelCollectorEndpoint}` },
                  { name: 'OTEL_SERVICE_NAME', value: 'flagd' },
                  { name: 'OTEL_TRACES_EXPORTER', value: 'otlp' },
                  { name: 'OTEL_METRICS_EXPORTER', value: 'otlp' },
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
                volumeMounts: [
                  {
                    name: 'flagd-config',
                    mountPath: '/etc/flagd',
                    readOnly: true,
                  },
                ],
                securityContext: {
                  allowPrivilegeEscalation: false,
                  readOnlyRootFilesystem: true,
                  capabilities: {
                    drop: ['ALL'],
                  },
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(8013),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                  failureThreshold: 3,
                },
                readinessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(8013),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                  failureThreshold: 3,
                },
              },
            ],
            volumes: [
              {
                name: 'flagd-config',
                configMap: {
                  name: 'flagd-config',
                },
              },
            ],
          },
        },
      },
    });

    // Service for gRPC and OFREP
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'flagd',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'flagd' },
        ports: [
          {
            name: 'grpc',
            port: 8013,
            targetPort: k8s.IntOrString.fromNumber(8013),
            protocol: 'TCP',
          },
          {
            name: 'ofrep',
            port: 8016,
            targetPort: k8s.IntOrString.fromNumber(8016),
            protocol: 'TCP',
          },
          {
            name: 'metrics',
            port: 8015,
            targetPort: k8s.IntOrString.fromNumber(8015),
            protocol: 'TCP',
          },
        ],
      },
    });

    // ServiceMonitor for Prometheus Operator (if available)
    // Note: This requires the Prometheus Operator CRD
    // Commenting out for now - can be enabled when ServiceMonitor CRD is imported
    /*
    new k8s.KubeCustomResource(this, 'service-monitor', {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'flagd',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: {
          matchLabels: {
            'app': 'flagd',
          },
        },
        endpoints: [
          {
            port: 'metrics',
            interval: '30s',
          },
        ],
      },
    });
    */
  }
}
