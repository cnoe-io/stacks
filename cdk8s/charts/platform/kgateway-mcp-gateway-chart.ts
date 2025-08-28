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

    // Create MCP Gateway using the kgateway GatewayClass
    new ApiObject(this, 'mcp-gateway', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'Gateway',
      metadata: {
        name: 'mcp-gateway',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-gateway',
          'app.kubernetes.io/component': 'gateway',
          'app.kubernetes.io/part-of': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          'gateway.kgateway.dev/description': 'Central MCP gateway for AI tool servers',
        },
      },
      spec: {
        gatewayClassName: 'kgateway',
        listeners: [
          {
            name: 'mcp-http',
            protocol: 'HTTP',
            port: 8080,
            hostname: 'mcp.kgateway.local',
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
          {
            name: 'mcp-https',
            protocol: 'HTTPS',
            port: 8443,
            hostname: 'mcp.kgateway.local',
            tls: {
              mode: 'Terminate',
              certificateRefs: [{
                kind: 'Secret',
                name: 'mcp-gateway-tls',
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
        addresses: [
          {
            type: 'IPAddress',
            value: '0.0.0.0', // Bind to all interfaces for vcluster access
          },
        ],
      },
    });

    // Create HTTP Gateway for general purpose routing
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

    // Create Service to expose MCP Gateway to vclusters
    new ApiObject(this, 'mcp-gateway-service', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'mcp-gateway',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-gateway',
          'app.kubernetes.io/component': 'service',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '21',
          'service.beta.kubernetes.io/azure-load-balancer-internal': 'true',
        },
      },
      spec: {
        type: 'LoadBalancer',
        selector: {
          'gateway.kgateway.dev/gateway-name': 'mcp-gateway',
        },
        ports: [
          {
            name: 'mcp-http',
            port: 8080,
            targetPort: 8080,
            protocol: 'TCP',
          },
          {
            name: 'mcp-https',
            port: 8443,
            targetPort: 8443,
            protocol: 'TCP',
          },
        ],
      },
    });

    // Create Service for HTTP Gateway
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
          'nginx.ingress.kubernetes.io/configuration-snippet': `
            proxy_set_header Accept-Encoding "";
            proxy_set_header Connection "";
            proxy_cache off;
            proxy_set_header X-Accel-Buffering no;
          `,
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
                    name: 'mcp-gateway',
                    port: {
                      number: 8080,
                    },
                  },
                },
              }],
            },
          },
          {
            host: 'kgateway.cnoe.localtest.me',
            http: {
              paths: [{
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: 'http-gateway',
                    port: {
                      number: 80,
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
          {
            hosts: ['kgateway.cnoe.localtest.me'],
            secretName: 'kgateway-tls-ingress',
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