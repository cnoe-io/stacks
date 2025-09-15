import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

/**
 * KGatewayMCPGatewayChart creates the Gateway resource for MCP protocol support
 * This enables centralized MCP endpoint with multiplexing, auth, and observability
 */
export class KGatewayMCPGatewayChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const kgatewayNamespace = 'kgateway-system';

    // Create AgentGateway for MCP protocol support
    new ApiObject(this, 'agentgateway', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'Gateway',
      metadata: {
        name: 'agentgateway',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'agentgateway',
          'app.kubernetes.io/component': 'gateway',
          'app.kubernetes.io/part-of': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          'gateway.kgateway.dev/description': 'AgentGateway for MCP server discovery and routing',
        },
      },
      spec: {
        gatewayClassName: 'agentgateway',
        listeners: [
          {
            name: 'http',
            protocol: 'HTTP',
            port: 8080,
            allowedRoutes: {
              namespaces: {
                from: 'All', // Allow routes from all namespaces
              },
              kinds: [{
                group: 'gateway.networking.k8s.io',
                kind: 'HTTPRoute',
              }],
            },
          },
          // HTTPS listener can be added later if needed
        ],
      },
    });

    // HTTP Gateway removed - using AgentGateway for MCP
    /*
    new ApiObject(this, 'http-gateway', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'Gateway',
      metadata: {
        name: 'http-gateway',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'http-gateway',
          'app.kubernetes.io/component': 'gateway',
          'app.kubernetes.io/part-of': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          'gateway.kgateway.dev/description': 'General purpose HTTP gateway',
        },
      },
      spec: {
        gatewayClassName: 'kgateway',
        listeners: [
          {
            name: 'http',
            protocol: 'HTTP',
            port: 80,
            allowedRoutes: {
              namespaces: {
                from: 'All',
              },
              kinds: [{
                group: 'gateway.networking.k8s.io',
                kind: 'HTTPRoute',
              }],
            },
          },
          {
            name: 'https',
            protocol: 'HTTPS',
            port: 443,
            tls: {
              mode: 'Terminate',
              certificateRefs: [{
                kind: 'Secret',
                name: 'http-gateway-tls',
                namespace: kgatewayNamespace,
              }],
            },
            allowedRoutes: {
              namespaces: {
                from: 'All',
              },
              kinds: [{
                group: 'gateway.networking.k8s.io',
                kind: 'HTTPRoute',
              }],
            },
          },
        ],
      },
    });
    */

    // Create Backend resource for MCP servers with dynamic discovery
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
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '25',
        },
      },
      spec: {
        type: 'MCP',
        mcp: {
          targets: [
            // Dynamic discovery using label selectors
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
            // Static targets for specific servers if needed
            {
              name: 'echo-mcp-static',
              static: {
                host: 'echo-mcp.mcp-servers.svc.cluster.local',
                port: 8080,
                protocol: 'SSE',
              },
            },
          ],
        },
      },
    });

    // Service is automatically created by the Gateway controller
    // No need to create it manually

    // Service for HTTP Gateway removed
    /*
    new ApiObject(this, 'http-gateway-service', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'http-gateway',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'http-gateway',
          'app.kubernetes.io/component': 'service',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '21',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: {
          'gateway.kgateway.dev/gateway-name': 'http-gateway',
        },
        ports: [
          {
            name: 'http',
            port: 80,
            targetPort: 80,
            protocol: 'TCP',
          },
          {
            name: 'https',
            port: 443,
            targetPort: 443,
            protocol: 'TCP',
          },
        ],
      },
    });

    */

    // Create Ingress to expose gateways externally
    new ApiObject(this, 'mcp-gateway-ingress', {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'mcp-gateway',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-gateway',
          'app.kubernetes.io/component': 'ingress',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '22',
          'nginx.ingress.kubernetes.io/proxy-body-size': '10m',
          'nginx.ingress.kubernetes.io/proxy-read-timeout': '600',
          'nginx.ingress.kubernetes.io/proxy-send-timeout': '600',
          'nginx.ingress.kubernetes.io/proxy-http-version': '1.1',
          // Enable WebSocket/SSE support for MCP
          'nginx.ingress.kubernetes.io/proxy-buffering': 'off',
        },
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [
          {
            host: 'mcp-gateway.cnoe.localtest.me',
            http: {
              paths: [{
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: 'agentgateway',
                    port: {
                      number: 8080,
                    },
                  },
                },
              }],
            },
          },
        ],
        tls: [
          {
            hosts: ['mcp-gateway.cnoe.localtest.me'],
            secretName: 'mcp-gateway-tls-ingress',
          },
        ],
      },
    });

    // Create BackendPolicy for MCP-specific configuration
    // NOTE: BackendPolicy CRD doesn't exist in kgateway, commenting out for now
    // The Backend CRD exists but has different structure
    /*
    new ApiObject(this, 'mcp-backend-policy', {
      apiVersion: 'gateway.kgateway.dev/v1alpha1',
      kind: 'BackendPolicy',
      metadata: {
        name: 'mcp-defaults',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-gateway',
          'app.kubernetes.io/component': 'policy',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '15',
        },
      },
      spec: {
        targetRef: {
          group: 'gateway.networking.k8s.io',
          kind: 'Gateway',
          name: 'mcp-gateway',
        },
        mcp: {
          discovery: {
            enabled: true,
            refreshInterval: '30s',
          },
          multiplexing: {
            enabled: true,
            maxConcurrentStreams: 100,
          },
          timeout: {
            connect: '10s',
            request: '60s',
            idle: '300s',
          },
          retries: {
            attempts: 3,
            perTryTimeout: '10s',
            retryOn: ['5xx', 'reset', 'connect-failure', 'refused-stream'],
          },
        },
        observability: {
          metrics: {
            enabled: true,
            includeMethodLabel: true,
            includeStatusCodeLabel: true,
          },
          tracing: {
            enabled: true,
            sampling: 0.1,
            propagation: ['w3c', 'b3'],
          },
          logging: {
            enabled: true,
            level: 'info',
            includeHeaders: false, // Privacy
            includeBody: false, // Privacy
          },
        },
        security: {
          cors: {
            enabled: true,
            allowOrigins: [
              'http://localhost:*',
              'https://*.cnoe.localtest.me',
            ],
            allowMethods: ['GET', 'POST', 'OPTIONS'],
            allowHeaders: ['Content-Type', 'Authorization', 'X-MCP-*'],
            exposeHeaders: ['X-MCP-Version', 'X-MCP-Tools'],
            maxAge: '86400s',
            allowCredentials: true,
          },
        },
      },
    });
    */
  }
}