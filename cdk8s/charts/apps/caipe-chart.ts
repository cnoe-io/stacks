/**
 * CaipeChart - Deploys CNOE AI Platform Engineering (CAIPE) via Helm chart
 *
 * This chart deploys the ai-platform-engineering multi-agent system with:
 * - supervisor-agent (main orchestrator)
 * - agent-argocd (ArgoCD operations)
 * - agent-github (GitHub operations)
 * - agent-backstage (Backstage catalog operations)
 *
 * Provides:
 * - Multi-agent coordination via supervisor
 * - Azure OpenAI integration for embeddings
 * - External Secrets for credential management
 *
 * Must be deployed after caipe-secrets ExternalSecrets
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeIngress } from '../../imports/k8s';

export interface CaipeChartProps extends ChartProps {
  /**
   * ai-platform-engineering Helm chart version
   * @default '0.3.0'
   */
  version?: string;

  /**
   * Namespace for CAIPE components
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Base host for ingress
   * Uses INGRESS_HOST environment variable if not specified
   */
  baseHost?: string;

  /**
   * External URL for supervisor-agent
   * Automatically derived from baseHost if not specified
   */
  externalUrl?: string;

  /**
   * Enable ArgoCD agent
   * @default true
   */
  enableArgocdAgent?: boolean;

  /**
   * Enable GitHub agent
   * @default true
   */
  enableGithubAgent?: boolean;

  /**
   * Enable Backstage agent
   * @default true
   */
  enableBackstageAgent?: boolean;
}

export class CaipeChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeChartProps = {}) {
    super(scope, id, props);

    const version = props.version || '0.3.0';
    const namespace = props.namespace || 'ai-platform-engineering';
    const baseHost = props.baseHost || process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const isKind = baseHost === 'cnoe.localtest.me';
    const portSuffix = isKind ? ':8443' : '';
    const externalUrl = props.externalUrl || `https://ai-platform-engineering.${baseHost}${portSuffix}`;

    // Agent enablement (core agents only by default)
    const enableArgocdAgent = props.enableArgocdAgent !== false;
    const enableGithubAgent = props.enableGithubAgent !== false;
    const enableBackstageAgent = props.enableBackstageAgent !== false;

    // Deploy ai-platform-engineering using official Helm chart from OCI registry
    new Helm(this, 'ai-platform-engineering', {
      chart: 'oci://ghcr.io/cnoe-io/helm-charts/ai-platform-engineering',
      version: version,
      namespace: namespace,
      releaseName: 'caipe',
      values: {
        // Enable selective components - only core agents, no RAG stack
        tags: {
          // Enable only the agents we need
          'agent-argocd': true,
          'agent-github': true,
          'agent-backstage': true,
          // Disable agents we don't have secrets for
          'agent-aws': false,
          'agent-confluence': false,
          'agent-jira': false,
          'agent-komodor': false,
          'agent-pagerduty': false,
          'agent-slack': false,
          'agent-splunk': false,
          'agent-webex': false,
          // Disable RAG stack for initial deployment
          'rag-stack': false,
        },

        // Main supervisor agent
        // Must use 'supervisor-agent' key (not 'ai-platform-engineering') per CNOE reference
        'supervisor-agent': {
          nameOverride: 'supervisor-agent',
          image: {
            repository: 'ghcr.io/cnoe-io/ai-platform-engineering',
            tag: '0.2.4',
            pullPolicy: 'IfNotPresent',
          },
          env: {
            EXTERNAL_URL: externalUrl,
            RAG_AGENT_PORT: 8099,
            // Agent connectivity settings
            AGENT_CONNECTIVITY_ENABLE_BACKGROUND: 'true',
            SKIP_AGENT_CONNECTIVITY_CHECK: 'false',
            // Orchestration settings
            FORCE_DEEP_AGENT_ORCHESTRATION: 'true',
            STREAM_SUB_AGENT_TOOL_OUTPUT: 'true',
            ENABLE_ARTIFACT_STREAMING: 'true',
          },
        },

        // Global configuration
        global: {
          // Disable slim mode for full functionality
          slim: {
            enabled: false,
          },

          // Disable External Secrets creation - we create them via CaipeSecretsChart
          externalSecrets: {
            enabled: false,
          },

          // Don't create agent secrets via Helm - we create them via ExternalSecrets
          agentSecrets: {
            create: false,
          },

          // LLM secrets already created via CaipeSecretsChart ExternalSecret
          llmSecrets: {
            create: false,
            secretName: 'llm-secret',
          },
        },

        // ArgoCD agent
        'agent-argocd': {
          enabled: enableArgocdAgent,
          nameOverride: 'agent-argocd',
          image: {
            repository: 'ghcr.io/cnoe-io/agent-argocd',
            tag: '0.2.4',
            pullPolicy: 'IfNotPresent',
          },
          mcp: {
            image: {
              repository: 'ghcr.io/cnoe-io/mcp-argocd',
              tag: '0.2.4',
              pullPolicy: 'IfNotPresent',
            },
            mode: 'http',
            port: 8000,
          },
          // Use pre-created secret from ExternalSecrets
          agentSecrets: {
            create: false,
            secretName: 'agent-argocd-secret',
          },
        },

        // GitHub agent
        'agent-github': {
          enabled: enableGithubAgent,
          nameOverride: 'agent-github',
          image: {
            repository: 'ghcr.io/cnoe-io/agent-github',
            tag: '0.2.4',
            pullPolicy: 'IfNotPresent',
          },
          mcp: {
            useRemoteMcpServer: true,
          },
          // Use pre-created secret from ExternalSecrets
          agentSecrets: {
            create: false,
            secretName: 'agent-github-secret',
          },
        },

        // Backstage agent
        'agent-backstage': {
          enabled: enableBackstageAgent,
          nameOverride: 'agent-backstage',
          image: {
            repository: 'ghcr.io/cnoe-io/agent-backstage',
            tag: '0.2.4',
            pullPolicy: 'IfNotPresent',
          },
          mcp: {
            image: {
              repository: 'ghcr.io/cnoe-io/mcp-backstage',
              tag: '0.2.4',
              pullPolicy: 'IfNotPresent',
            },
            mode: 'http',
            port: 8000,
          },
          // Use pre-created secret from ExternalSecrets
          agentSecrets: {
            create: false,
            secretName: 'agent-backstage-secret',
          },
        },

        // Disable agents we don't have secrets for
        'agent-aws': { enabled: false },
        'agent-confluence': { enabled: false },
        'agent-jira': { enabled: false },
        'agent-komodor': { enabled: false },
        'agent-pagerduty': { enabled: false },
        'agent-slack': { enabled: false },
        'agent-splunk': { enabled: false },
        'agent-webex': { enabled: false },

        // Disable RAG stack for initial deployment (can be enabled later)
        'rag-stack': {
          enabled: false,
        },
      },
    });

    // Create Ingress for ai-platform-engineering (supervisor-agent)
    const caipeHost = `ai-platform-engineering.${baseHost}`;
    new KubeIngress(this, 'caipe-ingress', {
      metadata: {
        name: 'ai-platform-engineering',
        namespace: namespace,
        annotations: {
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
            host: caipeHost,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'caipe-supervisor-agent',
                      port: {
                        number: 8000,
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
