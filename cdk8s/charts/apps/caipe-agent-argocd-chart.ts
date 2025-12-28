/**
 * CaipeAgentArgocdChart - ArgoCD Agent for CAIPE
 *
 * Deploys the ArgoCD agent that provides:
 * - Natural language ArgoCD operations
 * - Application status queries
 * - Sync and management operations
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

export interface CaipeAgentArgocdChartProps extends ChartProps {
  /**
   * Namespace for ArgoCD Agent
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * ArgoCD Agent image
   * @default 'ghcr.io/cnoe-io/agent-argocd:0.2.4'
   */
  image?: string;

  /**
   * Secret name for ArgoCD credentials
   * @default 'agent-argocd-secret'
   */
  argocdSecretName?: string;

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

export class CaipeAgentArgocdChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeAgentArgocdChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/agent-argocd:latest';
    const argocdSecretName = props.argocdSecretName || 'agent-argocd-secret';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.agents;

    const labels = getCaipeAgentLabels('agent-argocd');
    const selectorLabels = {
      'app.kubernetes.io/name': 'agent-argocd',
      'app.kubernetes.io/instance': 'caipe-agent-argocd',
      'app': 'agent-argocd',
    };

    // Deployment for ArgoCD Agent
    new k8s.KubeDeployment(this, 'agent-argocd', {
      metadata: {
        name: 'agent-argocd',
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
                name: 'agent-argocd',
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
                  { name: 'AGENT_NAME', value: 'agent-argocd' },
                  { name: 'AGENT_DESCRIPTION', value: 'ArgoCD agent for GitOps operations' },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: argocdSecretName,
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

    // Service for ArgoCD Agent
    new k8s.KubeService(this, 'agent-argocd-svc', {
      metadata: {
        name: 'agent-argocd',
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
