/**
 * CaipeSupervisorChart - Supervisor Agent for CAIPE
 *
 * Deploys the supervisor-agent, the central orchestrator that:
 * - Routes user requests to appropriate sub-agents
 * - Coordinates multi-agent operations via A2A protocol
 * - Aggregates responses from sub-agents
 * - Provides the main chat interface
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_RESOURCE_LIMITS,
  CAIPE_OBSERVABILITY,
  getCaipeAgentLabels,
  getSupervisorAgentEnvVars,
  getCaipeSupervisorUrl,
  getCaipeIngressHost,
} from '../../lib/caipe-helpers';

export interface CaipeSupervisorChartProps extends ChartProps {
  /**
   * Namespace for Supervisor Agent
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Supervisor Agent image
   * @default 'ghcr.io/cnoe-io/ai-platform-engineering:0.2.4'
   */
  image?: string;

  /**
   * Secret name for LLM credentials
   * @default 'llm-secret'
   */
  llmSecretName?: string;

  /**
   * Base host for ingress/external URL
   * @default 'cnoe.localtest.me'
   */
  baseHost?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '50'
   */
  syncWave?: string;
}

export class CaipeSupervisorChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeSupervisorChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/ai-platform-engineering:latest';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const baseHost = props.baseHost || process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const isKind = baseHost === 'cnoe.localtest.me';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.supervisor;

    const labels = getCaipeAgentLabels('supervisor-agent');
    const selectorLabels = {
      'app.kubernetes.io/name': 'supervisor-agent',
      'app.kubernetes.io/instance': 'caipe-supervisor-agent',
      'app': 'supervisor-agent',
    };

    const externalUrl = getCaipeSupervisorUrl(baseHost, isKind);
    const envVars = getSupervisorAgentEnvVars(externalUrl);
    const ingressHost = getCaipeIngressHost('ai-platform-engineering', baseHost);

    // Deployment for Supervisor Agent
    new k8s.KubeDeployment(this, 'supervisor-agent', {
      metadata: {
        name: 'supervisor-agent',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: selectorLabels,
        },
        template: {
          metadata: {
            labels: { ...labels, ...selectorLabels },
          },
          spec: {
            containers: [
              {
                name: 'supervisor-agent',
                image: image,
                command: ['python', '-m', 'ai_platform_engineering.multi_agents', 'platform-engineer'],
                ports: [
                  {
                    name: 'http',
                    containerPort: CAIPE_PORTS.supervisorAgent,
                  },
                ],
                env: [
                  // External URL for callbacks
                  { name: 'EXTERNAL_URL', value: envVars.EXTERNAL_URL },
                  // Agent connectivity settings
                  { name: 'AGENT_CONNECTIVITY_ENABLE_BACKGROUND', value: envVars.AGENT_CONNECTIVITY_ENABLE_BACKGROUND },
                  { name: 'SKIP_AGENT_CONNECTIVITY_CHECK', value: envVars.SKIP_AGENT_CONNECTIVITY_CHECK },
                  // Orchestration settings
                  { name: 'FORCE_DEEP_AGENT_ORCHESTRATION', value: envVars.FORCE_DEEP_AGENT_ORCHESTRATION },
                  { name: 'STREAM_SUB_AGENT_TOOL_OUTPUT', value: envVars.STREAM_SUB_AGENT_TOOL_OUTPUT },
                  { name: 'ENABLE_ARTIFACT_STREAMING', value: envVars.ENABLE_ARTIFACT_STREAMING },
                  // RAG configuration
                  { name: 'RAG_AGENT_PORT', value: envVars.RAG_AGENT_PORT },
                  { name: 'RAG_SERVER_URL', value: `http://rag-server.${namespace}.svc.cluster.local:${CAIPE_PORTS.ragServer}` },
                  // Sub-agent endpoints
                  { name: 'AGENT_ARGOCD_URL', value: `http://agent-argocd.${namespace}.svc.cluster.local:${CAIPE_PORTS.mcpHttp}` },
                  { name: 'AGENT_GITHUB_URL', value: `http://agent-github.${namespace}.svc.cluster.local:${CAIPE_PORTS.mcpHttp}` },
                  { name: 'AGENT_BACKSTAGE_URL', value: `http://agent-backstage.${namespace}.svc.cluster.local:${CAIPE_PORTS.mcpHttp}` },
                  // Observability - cnoe-agent-utils tracing control
                  { name: 'ENABLE_TRACING', value: CAIPE_OBSERVABILITY.tracing.enabled },
                  // Observability - Prometheus metrics
                  { name: 'METRICS_ENABLED', value: CAIPE_OBSERVABILITY.metrics.enabled },
                  { name: 'METRICS_PORT', value: String(CAIPE_PORTS.supervisorAgent) },
                  // Observability - OpenTelemetry for distributed tracing (Tempo)
                  { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: CAIPE_OBSERVABILITY.otel.grpcEndpoint },
                  { name: 'OTEL_SERVICE_NAME', value: 'caipe-supervisor-agent' },
                  // Observability - Langfuse for LLM-specific tracing
                  { name: 'LANGFUSE_ENABLED', value: CAIPE_OBSERVABILITY.langfuse.enabled },
                  { name: 'LANGFUSE_HOST', value: CAIPE_OBSERVABILITY.langfuse.host },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: llmSecretName,
                    },
                  },
                  {
                    // Langfuse API credentials for tracing
                    secretRef: {
                      name: 'caipe-langfuse-credentials',
                    },
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('256Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.supervisorAgent.memory),
                    cpu: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.supervisorAgent.cpu),
                  },
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.supervisorAgent),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                },
                readinessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.supervisorAgent),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                },
              },
            ],
          },
        },
      },
    });

    // Service for Supervisor Agent
    new k8s.KubeService(this, 'supervisor-agent-svc', {
      metadata: {
        name: 'supervisor-agent',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: selectorLabels,
        ports: [
          {
            name: 'http',
            port: CAIPE_PORTS.supervisorAgent,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.supervisorAgent),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });

    // Ingress for Supervisor Agent
    new k8s.KubeIngress(this, 'supervisor-agent-ingress', {
      metadata: {
        name: 'ai-platform-engineering',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          'nginx.ingress.kubernetes.io/proxy-body-size': '10m',
          'nginx.ingress.kubernetes.io/proxy-read-timeout': '300',
          'nginx.ingress.kubernetes.io/proxy-send-timeout': '300',
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
                      name: 'supervisor-agent',
                      port: {
                        number: CAIPE_PORTS.supervisorAgent,
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
