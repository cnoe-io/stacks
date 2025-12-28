/**
 * CaipeAgentBackstageChart - Backstage Agent for CAIPE
 *
 * Deploys the Backstage agent that provides:
 * - Software catalog queries
 * - Service discovery
 * - Component relationship exploration
 * - MCP HTTP mode for supervisor communication
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
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
   * @default 'ghcr.io/cnoe-io/agent-backstage:0.2.4'
   */
  image?: string;

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
    const backstageSecretName = props.backstageSecretName || 'agent-backstage-secret';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.agents;

    const labels = getCaipeAgentLabels('agent-backstage');
    const selectorLabels = {
      'app.kubernetes.io/name': 'agent-backstage',
      'app.kubernetes.io/instance': 'caipe-agent-backstage',
      'app': 'agent-backstage',
    };

    // Deployment for Backstage Agent
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
              {
                name: 'agent-backstage',
                image: image,
                ports: [
                  {
                    name: 'mcp-http',
                    containerPort: CAIPE_PORTS.mcpHttp,
                  },
                ],
                env: [
                  // MCP HTTP mode configuration
                  { name: 'MCP_MODE', value: 'http' },
                  { name: 'MCP_HTTP_PORT', value: String(CAIPE_PORTS.mcpHttp) },
                  // Agent identification
                  { name: 'AGENT_NAME', value: 'agent-backstage' },
                  { name: 'AGENT_DESCRIPTION', value: 'Backstage agent for software catalog operations' },
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
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.mcpHttp),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.mcpHttp),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
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
            name: 'mcp-http',
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
