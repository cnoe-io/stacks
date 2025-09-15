import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

/**
 * KGatewayMCPRoutesChart creates HTTPRoute resources for routing to MCP servers
 * These routes enable path-based routing to different MCP tool servers
 */
export class KGatewayMCPRoutesChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const kgatewayNamespace = 'kgateway-system';
    const mcpServersNamespace = 'mcp-servers';

    // Create main MCP HTTPRoute that references the Backend
    new ApiObject(this, 'mcp-main-route', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: 'mcp',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp',
          'app.kubernetes.io/component': 'route',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '30',
          'mcp.kgateway.dev/description': 'Main MCP route to Backend',
        },
      },
      spec: {
        parentRefs: [
          {
            name: 'agentgateway',
            namespace: kgatewayNamespace,
          },
        ],
        rules: [
          {
            backendRefs: [
              {
                group: 'gateway.kgateway.dev',
                kind: 'Backend',
                name: 'mcp-backend',
              },
            ],
          },
        ],
      },
    });

    // Create HTTPRoute for Grafana MCP server
    new ApiObject(this, 'grafana-mcp-route', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: 'grafana-mcp',
        namespace: mcpServersNamespace,
        labels: {
          'app.kubernetes.io/name': 'grafana-mcp',
          'app.kubernetes.io/component': 'route',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/server': 'grafana',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '30',
          'mcp.kgateway.dev/tools': 'grafana_dashboard,grafana_datasource,grafana_alert',
        },
      },
      spec: {
        parentRefs: [
          {
            name: 'agentgateway',
            namespace: kgatewayNamespace,
          },
        ],
        hostnames: ['mcp-gateway.cnoe.localtest.me'],
        rules: [
          {
            matches: [
              {
                path: {
                  type: 'PathPrefix',
                  value: '/mcp/grafana',
                },
              },
            ],
            filters: [
              {
                type: 'URLRewrite',
                urlRewrite: {
                  path: {
                    type: 'ReplacePrefixMatch',
                    replacePrefixMatch: '/',
                  },
                },
              },
              {
                type: 'RequestHeaderModifier',
                requestHeaderModifier: {
                  add: [
                    {
                      name: 'X-MCP-Gateway',
                      value: 'kgateway',
                    },
                    {
                      name: 'X-MCP-Version',
                      value: 'v1',
                    },
                  ],
                },
              },
            ],
            backendRefs: [
              {
                name: 'grafana-mcp',
                namespace: mcpServersNamespace,
                port: 8080,
                weight: 100,
              },
            ],
          },
        ],
      },
    });

    // Create HTTPRoute for Echo MCP server
    new ApiObject(this, 'echo-mcp-route', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: 'echo-mcp',
        namespace: mcpServersNamespace,
        labels: {
          'app.kubernetes.io/name': 'echo-mcp',
          'app.kubernetes.io/component': 'route',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/server': 'echo',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '30',
          'mcp.kgateway.dev/tools': 'echo',
        },
      },
      spec: {
        parentRefs: [
          {
            name: 'agentgateway',
            namespace: kgatewayNamespace,
          },
        ],
        hostnames: ['mcp-gateway.cnoe.localtest.me'],
        rules: [
          {
            matches: [
              {
                path: {
                  type: 'PathPrefix',
                  value: '/mcp/echo',
                },
              },
            ],
            filters: [
              {
                type: 'URLRewrite',
                urlRewrite: {
                  path: {
                    type: 'ReplacePrefixMatch',
                    replacePrefixMatch: '/',
                  },
                },
              },
              {
                type: 'RequestHeaderModifier',
                requestHeaderModifier: {
                  add: [
                    {
                      name: 'X-MCP-Gateway',
                      value: 'kgateway',
                    },
                  ],
                },
              },
            ],
            backendRefs: [
              {
                name: 'echo-mcp',
                namespace: mcpServersNamespace,
                port: 8080,
                weight: 100,
              },
            ],
          },
        ],
      },
    });

    // Create HTTPRoute for Text Tools MCP server
    new ApiObject(this, 'text-tools-mcp-route', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: 'text-tools-mcp',
        namespace: mcpServersNamespace,
        labels: {
          'app.kubernetes.io/name': 'text-tools-mcp',
          'app.kubernetes.io/component': 'route',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/server': 'text-tools',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '30',
          'mcp.kgateway.dev/tools': 'text_transform,text_analyze,text_generate',
        },
      },
      spec: {
        parentRefs: [
          {
            name: 'agentgateway',
            namespace: kgatewayNamespace,
          },
        ],
        hostnames: ['mcp-gateway.cnoe.localtest.me'],
        rules: [
          {
            matches: [
              {
                path: {
                  type: 'PathPrefix',
                  value: '/mcp/text-tools',
                },
              },
            ],
            filters: [
              {
                type: 'URLRewrite',
                urlRewrite: {
                  path: {
                    type: 'ReplacePrefixMatch',
                    replacePrefixMatch: '/',
                  },
                },
              },
              {
                type: 'RequestHeaderModifier',
                requestHeaderModifier: {
                  add: [
                    {
                      name: 'X-MCP-Gateway',
                      value: 'kgateway',
                    },
                  ],
                },
              },
            ],
            backendRefs: [
              {
                name: 'text-tools-mcp',
                namespace: mcpServersNamespace,
                port: 8080,
                weight: 100,
              },
            ],
          },
        ],
      },
    });

    // Create a catch-all route for MCP discovery endpoint
    new ApiObject(this, 'mcp-discovery-route', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: 'mcp-discovery',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-discovery',
          'app.kubernetes.io/component': 'route',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '31',
          'mcp.kgateway.dev/description': 'Discovery endpoint for available MCP servers',
        },
      },
      spec: {
        parentRefs: [
          {
            name: 'mcp-gateway',
            namespace: kgatewayNamespace,
          },
        ],
        hostnames: ['mcp-gateway.cnoe.localtest.me'],
        rules: [
          {
            matches: [
              {
                path: {
                  type: 'Exact',
                  value: '/mcp/discovery',
                },
              },
              {
                path: {
                  type: 'Exact',
                  value: '/.well-known/mcp-servers',
                },
              },
            ],
            filters: [
              {
                type: 'ResponseHeaderModifier',
                responseHeaderModifier: {
                  add: [
                    {
                      name: 'Content-Type',
                      value: 'application/json',
                    },
                    {
                      name: 'Cache-Control',
                      value: 'max-age=60',
                    },
                  ],
                },
              },
            ],
            // This would typically route to a discovery service
            // For now, we'll use a static response or dedicated discovery pod
            backendRefs: [
              {
                name: 'mcp-discovery-service',
                namespace: kgatewayNamespace,
                port: 8080,
                weight: 100,
              },
            ],
          },
        ],
      },
    });

    // Create HTTPRoute for health check endpoint
    new ApiObject(this, 'mcp-health-route', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: 'mcp-health',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-health',
          'app.kubernetes.io/component': 'route',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '31',
        },
      },
      spec: {
        parentRefs: [
          {
            name: 'mcp-gateway',
            namespace: kgatewayNamespace,
          },
        ],
        rules: [
          {
            matches: [
              {
                path: {
                  type: 'Exact',
                  value: '/health',
                },
              },
              {
                path: {
                  type: 'Exact',
                  value: '/healthz',
                },
              },
            ],
            filters: [
              {
                type: 'ResponseHeaderModifier',
                responseHeaderModifier: {
                  add: [
                    {
                      name: 'X-MCP-Gateway-Health',
                      value: 'healthy',
                    },
                  ],
                },
              },
            ],
            // Route to any healthy backend for basic health check
            backendRefs: [
              {
                name: 'echo-mcp',
                namespace: mcpServersNamespace,
                port: 8080,
                weight: 100,
              },
            ],
          },
        ],
      },
    });

    // RoutePolicy doesn't exist in kgateway CRDs - removed
    // Use TrafficPolicy or HTTPListenerPolicy instead if needed
    /*
    new ApiObject(this, 'mcp-route-policy', {
      apiVersion: 'gateway.kgateway.dev/v1alpha1',
      kind: 'RoutePolicy',
      metadata: {
        name: 'mcp-routes-policy',
        namespace: mcpServersNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-routes',
          'app.kubernetes.io/component': 'policy',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '25',
        },
      },
      spec: {
        targetRef: {
          group: 'gateway.networking.k8s.io',
          kind: 'HTTPRoute',
          namespace: mcpServersNamespace,
        },
        loadBalancing: {
          type: 'RoundRobin',
          consistentHash: {
            header: 'X-Session-ID',
          },
        },
        timeout: {
          request: '60s',
          idle: '300s',
        },
        retry: {
          attempts: 3,
          perTryTimeout: '10s',
          retryOn: ['5xx', 'reset', 'connect-failure'],
          retryConditions: [
            {
              statusCodes: [502, 503, 504],
            },
          ],
        },
        circuitBreaker: {
          consecutiveErrors: 5,
          interval: '30s',
          baseEjectionTime: '30s',
          maxEjectionPercent: 50,
          splitExternalLocalOriginErrors: true,
        },
        healthCheck: {
          path: '/health',
          interval: '10s',
          timeout: '3s',
          unhealthyThreshold: 2,
          healthyThreshold: 2,
        },
      },
    });
    */
  }
}