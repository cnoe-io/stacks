/**
 * CaipeAgentBackstageChart - Backstage Agent for CAIPE
 *
 * Deploys the Backstage agent with MCP sidecar pattern:
 * - Agent container connects to MCP sidecar via HTTP
 * - MCP sidecar runs the Backstage MCP server
 * - Software catalog queries
 * - Service discovery
 * - Component relationship exploration
 *
 * Reference: https://github.com/cnoe-io/ai-platform-engineering
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_OBSERVABILITY,
  getCaipeAgentLabels,
} from '../../lib/caipe-helpers';

export interface CaipeAgentBackstageChartProps extends ChartProps {
  /**
   * Namespace for Backstage Agent
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Backstage Agent image
   * @default 'ghcr.io/cnoe-io/agent-backstage:latest'
   */
  image?: string;

  /**
   * MCP Backstage server image
   * @default 'ghcr.io/cnoe-io/mcp-backstage:stable'
   */
  mcpImage?: string;

  /**
   * Secret name for Backstage credentials
   * @default 'agent-backstage-secret'
   */
  backstageSecretName?: string;

  /**
   * Secret name for LLM credentials
   * @default 'llm-secret'
   */
  llmSecretName?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '100'
   */
  syncWave?: string;
}

export class CaipeAgentBackstageChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeAgentBackstageChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/agent-backstage:latest';
    const mcpImage = props.mcpImage || 'ghcr.io/cnoe-io/mcp-backstage:stable';
    const backstageSecretName = props.backstageSecretName || 'agent-backstage-secret';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.agents;

    // MCP sidecar port - agent connects to this internally
    const mcpSidecarPort = 3000;

    const labels = getCaipeAgentLabels('agent-backstage');
    const selectorLabels = {
      'app.kubernetes.io/name': 'agent-backstage',
      'app.kubernetes.io/instance': 'caipe-agent-backstage',
      'app': 'agent-backstage',
    };

    // Deployment for Backstage Agent with MCP sidecar
    new k8s.KubeDeployment(this, 'agent-backstage', {
      metadata: {
        name: 'agent-backstage',
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
              // Main agent container
              {
                name: 'agent-backstage',
                image: image,
                ports: [
                  {
                    name: 'a2a-http',
                    containerPort: CAIPE_PORTS.mcpHttp,
                  },
                ],
                env: [
                  // MCP HTTP mode - connects to MCP sidecar
                  { name: 'MCP_MODE', value: 'http' },
                  // Connect to MCP sidecar running in the same pod
                  { name: 'MCP_HOST', value: 'localhost' },
                  { name: 'MCP_PORT', value: String(mcpSidecarPort) },
                  // A2A server listens on port 8000
                  { name: 'MCP_HTTP_PORT', value: String(CAIPE_PORTS.mcpHttp) },
                  // Agent identification
                  { name: 'AGENT_NAME', value: 'agent-backstage' },
                  { name: 'AGENT_DESCRIPTION', value: 'Backstage agent for software catalog operations' },
                  // Observability - cnoe-agent-utils tracing control
                  { name: 'ENABLE_TRACING', value: CAIPE_OBSERVABILITY.tracing.enabled },
                  // Observability - OpenTelemetry for distributed tracing (Tempo)
                  { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: CAIPE_OBSERVABILITY.otel.grpcEndpoint },
                  { name: 'OTEL_SERVICE_NAME', value: 'caipe-agent-backstage' },
                  // Observability - Langfuse for LLM-specific tracing
                  { name: 'LANGFUSE_ENABLED', value: CAIPE_OBSERVABILITY.langfuse.enabled },
                  { name: 'LANGFUSE_HOST', value: CAIPE_OBSERVABILITY.langfuse.host },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: backstageSecretName,
                    },
                  },
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
                    memory: k8s.Quantity.fromString('128Mi'),
                    cpu: k8s.Quantity.fromString('50m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('512Mi'),
                    cpu: k8s.Quantity.fromString('250m'),
                  },
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.mcpHttp),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                },
                readinessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.mcpHttp),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                },
              },
              // MCP sidecar container - runs the Backstage MCP server
              {
                name: 'mcp-backstage',
                image: mcpImage,
                ports: [
                  {
                    name: 'mcp',
                    containerPort: mcpSidecarPort,
                  },
                ],
                env: [
                  { name: 'MCP_MODE', value: 'http' },
                  { name: 'MCP_HOST', value: '0.0.0.0' },
                  { name: 'MCP_PORT', value: String(mcpSidecarPort) },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: backstageSecretName,
                    },
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('64Mi'),
                    cpu: k8s.Quantity.fromString('25m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('256Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(mcpSidecarPort),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                },
                readinessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(mcpSidecarPort),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 5,
                  timeoutSeconds: 3,
                },
              },
            ],
          },
        },
      },
    });

    // Service for Backstage Agent
    new k8s.KubeService(this, 'agent-backstage-svc', {
      metadata: {
        name: 'agent-backstage',
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
            name: 'a2a-http',
            port: CAIPE_PORTS.mcpHttp,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.mcpHttp),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });
  }
}
