/**
 * KagentChart - Deploys kagent AI Agent Framework via Helm chart
 *
 * This chart deploys kagent v0.7.4 with:
 * - kagent-controller (manages Agent, ModelConfig, MCPServer CRDs)
 * - kagent-ui (Next.js dashboard for agent management)
 * - kmcp integration (bundled by default since v0.7)
 *
 * Provides:
 * - AI agent lifecycle management
 * - LLM provider integration (OpenAI, Anthropic, Gemini)
 * - MCP server tool orchestration
 * - Multi-agent coordination via A2A protocol
 *
 * Must be deployed after kagent CRDs
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeIngress } from '../../imports/k8s';

export interface KagentChartProps extends ChartProps {
  /**
   * kagent Helm chart version
   * @default '0.7.4'
   */
  version?: string;

  /**
   * Namespace for kagent components
   * @default 'kagent'
   */
  namespace?: string;

  /**
   * Default LLM provider
   * @default 'openAI'
   */
  defaultProvider?: 'openAI' | 'anthropic' | 'gemini';

  /**
   * Enable kmcp controller (bundled since v0.7)
   * @default true
   */
  enableKmcp?: boolean;

  /**
   * Controller replicas
   * @default 1
   */
  replicas?: number;

  /**
   * Secret name containing LLM API keys
   * @default 'kagent-llm-providers'
   */
  apiKeySecretRef?: string;
}

export class KagentChart extends Chart {
  constructor(scope: Construct, id: string, props: KagentChartProps = {}) {
    super(scope, id, props);

    const version = props.version || '0.7.4';
    const namespace = props.namespace || 'kagent';
    const defaultProvider = props.defaultProvider || 'openAI';
    const enableKmcp = props.enableKmcp !== false; // Default true
    const replicas = props.replicas || 1;
    const apiKeySecretRef = props.apiKeySecretRef || 'kagent-llm-providers';

    // Determine ingress host from environment
    const baseHost = process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const kagentHost = `kagent.${baseHost}`;

    // Deploy kagent using official Helm chart from OCI registry
    new Helm(this, 'kagent', {
      chart: 'oci://ghcr.io/kagent-dev/kagent/helm/kagent',
      version: version,
      namespace: namespace,
      releaseName: 'kagent',
      values: {
        // Namespace for kagent components
        namespace: namespace,

        // Controller configuration
        controller: {
          replicas: replicas,
          logLevel: 'info',
          resources: {
            requests: {
              cpu: '100m',
              memory: '128Mi',
            },
            limits: {
              cpu: '1000m',
              memory: '1Gi',
            },
          },
        },

        // UI/Dashboard configuration
        ui: {
          enabled: true,
          replicas: 1,
          service: {
            type: 'ClusterIP',
            port: 8080,
            targetPort: 8080,
          },
          ingress: {
            enabled: true,
            className: 'nginx',
            annotations: {
              'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
            },
            hosts: [
              {
                host: kagentHost,
                paths: [
                  {
                    path: '/',
                    pathType: 'Prefix',
                  },
                ],
              },
            ],
          },
          resources: {
            requests: {
              cpu: '100m',
              memory: '256Mi',
            },
            limits: {
              cpu: '1000m',
              memory: '1Gi',
            },
          },
        },

        // LLM Provider configuration (using secret references for API keys)
        providers: {
          default: defaultProvider,
          openAI: {
            enabled: true,
            model: 'gpt-4',
            apiKeySecretRef: apiKeySecretRef,
            apiKeySecretKey: 'OPENAI_API_KEY',
          },
          anthropic: {
            enabled: true,
            model: 'claude-3-5-sonnet-20241022',
            apiKeySecretRef: apiKeySecretRef,
            apiKeySecretKey: 'ANTHROPIC_API_KEY',
          },
          gemini: {
            enabled: true,
            model: 'gemini-2.0-flash-exp',
            apiKeySecretRef: apiKeySecretRef,
            apiKeySecretKey: 'GEMINI_API_KEY',
          },
        },

        // KMCP configuration (bundled since v0.7)
        kmcp: {
          enabled: enableKmcp,
          controller: {
            replicas: 1,
            resources: {
              requests: {
                cpu: '100m',
                memory: '256Mi',
              },
              limits: {
                cpu: '1000m',
                memory: '1Gi',
              },
            },
          },
        },

        // Database configuration (SQLite for local dev)
        database: {
          type: 'sqlite',
          sqlite: {
            path: '/data/kagent.db',
          },
          persistence: {
            enabled: true,
            storageClass: '',
            size: '1Gi',
            accessModes: ['ReadWriteOnce'],
          },
        },

        // Security context - NOTE: Do not override global securityContext
        // The kagent Helm chart v0.7.4 has a bug where it applies fsGroup
        // to container-level securityContext instead of pod-level.
        // Let the chart use its defaults.
        // securityContext: {
        //   runAsNonRoot: true,
        //   runAsUser: 1000,
        //   fsGroup: 1000,
        // },

        // RBAC configuration
        rbac: {
          create: true,
          clusterRole: true,
        },

        // Service account
        serviceAccount: {
          create: true,
          name: 'kagent',
          annotations: {},
        },

        // Global settings
        global: {
          image: {
            pullPolicy: 'IfNotPresent',
          },
        },
      },
    });

    // Create Ingress for kagent UI (not supported by Helm chart values)
    new KubeIngress(this, 'kagent-ui-ingress', {
      metadata: {
        name: 'kagent-ui',
        namespace: namespace,
        annotations: {
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
        },
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [
          {
            host: kagentHost,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'kagent-ui',
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
      },
    });
  }
}
