/**
 * CaipeAgentGithubChart - GitHub Agent for CAIPE
 *
 * Deploys the GitHub agent that provides:
 * - Repository queries and management
 * - Issue and PR operations
 * - Code search capabilities
 * - Remote MCP Server mode for supervisor communication
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

export interface CaipeAgentGithubChartProps extends ChartProps {
  /**
   * Namespace for GitHub Agent
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * GitHub Agent image
   * @default 'ghcr.io/cnoe-io/agent-github:0.2.4'
   */
  image?: string;

  /**
   * Secret name for GitHub credentials
   * @default 'agent-github-secret'
   */
  githubSecretName?: string;

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

export class CaipeAgentGithubChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeAgentGithubChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/agent-github:latest';
    const githubSecretName = props.githubSecretName || 'agent-github-secret';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.agents;

    const labels = getCaipeAgentLabels('agent-github');
    const selectorLabels = {
      'app.kubernetes.io/name': 'agent-github',
      'app.kubernetes.io/instance': 'caipe-agent-github',
      'app': 'agent-github',
    };

    // Deployment for GitHub Agent
    new k8s.KubeDeployment(this, 'agent-github', {
      metadata: {
        name: 'agent-github',
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
                name: 'agent-github',
                image: image,
                ports: [
                  {
                    name: 'mcp-http',
                    containerPort: CAIPE_PORTS.mcpHttp,
                  },
                ],
                env: [
                  // HTTP mode - connects to GitHub Copilot API MCP server
                  { name: 'MCP_MODE', value: 'http' },
                  // MCP_HTTP_PORT: A2A server listens on this port (8000)
                  { name: 'MCP_HTTP_PORT', value: String(CAIPE_PORTS.mcpHttp) },
                  // Agent identification
                  { name: 'AGENT_NAME', value: 'agent-github' },
                  { name: 'AGENT_DESCRIPTION', value: 'GitHub agent for repository operations' },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: githubSecretName,
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
            ],
          },
        },
      },
    });

    // Service for GitHub Agent
    new k8s.KubeService(this, 'agent-github-svc', {
      metadata: {
        name: 'agent-github',
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
