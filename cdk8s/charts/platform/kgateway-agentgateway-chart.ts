import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * KGatewayAgentGatewayChart creates the AgentGateway Backend resource
 * This enables agent-to-agent (A2A) and MCP communication through kgateway
 */
export class KGatewayAgentGatewayChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const kgatewayNamespace = 'kgateway-system';

    // AgentGateway is configured through the Gateway and GatewayClass
    // No separate Backend resource needed for AgentGateway itself

    // Create MCP Backend resource
    new ApiObject(this, 'mcp-backend', {
      apiVersion: 'gateway.kgateway.dev/v1alpha1',
      kind: 'Backend',
      metadata: {
        name: 'mcp-backend',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-backend',
          'app.kubernetes.io/component': 'backend',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/protocol': 'mcp',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          'mcp.kgateway.dev/description': 'Backend for MCP server communication',
        },
      },
      spec: {
        type: 'MCP',
        mcp: {
          targets: [
            {
              name: 'mcp-servers-dynamic',
              selector: {
                service: {
                  matchLabels: {
                    'mcp.kgateway.dev/enabled': 'true',
                  },
                },
              },
            },
            {
              name: 'echo-mcp-static',
              static: {
                host: 'echo-mcp.mcp-servers.svc.cluster.local',
                port: 8080,
                protocol: 'SSE',
              },
            },
          ],
          // MCP protocol configuration
          protocol: {
            version: 'v1',
            transport: 'http',
          },
          // Server discovery
          discovery: {
            enabled: true,
            refreshInterval: '30s',
          },
          // Connection pooling
          connectionPool: {
            maxConnections: 100,
            connectTimeout: '10s',
            idleTimeout: '60s',
          },
          // Health checks
          healthCheck: {
            enabled: true,
            interval: '10s',
            timeout: '3s',
            healthyThreshold: 2,
            unhealthyThreshold: 3,
          },
          // Load balancing
          loadBalancing: {
            algorithm: 'round_robin',
            stickySession: {
              enabled: true,
              cookieName: 'mcp-session',
              ttl: '1h',
            },
          },
        },
      },
    });

    // Create authentication tokens secret
    new k8s.KubeSecret(this, 'agentgateway-tokens', {
      metadata: {
        name: 'agentgateway-tokens',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'agentgateway-tokens',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '15',
          'external-secrets.io/managed': 'true',
        },
      },
      stringData: {
        'agent-tokens': JSON.stringify({
          agents: [
            {
              name: 'claude',
              token: 'placeholder-will-be-replaced-by-external-secrets',
            },
            {
              name: 'openai',
              token: 'placeholder-will-be-replaced-by-external-secrets',
            },
            {
              name: 'gemini',
              token: 'placeholder-will-be-replaced-by-external-secrets',
            },
          ],
        }),
      },
    });

    // Create ExternalSecret for AgentGateway tokens from 1Password
    new ApiObject(this, 'agentgateway-tokens-external-secret', {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: {
        name: 'agentgateway-tokens',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'agentgateway-tokens',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '16',
        },
      },
      spec: {
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: 'ClusterSecretStore',
        },
        target: {
          name: 'agentgateway-tokens',
          creationPolicy: 'Owner',
          template: {
            engineVersion: 'v2',
            data: {
              'agent-tokens': '{{ .agentTokens }}',
            },
          },
        },
        data: [
          {
            secretKey: 'agentTokens',
            remoteRef: {
              key: 'AGENTGATEWAY-TOKENS',
            },
          },
        ],
      },
    });
  }
}
