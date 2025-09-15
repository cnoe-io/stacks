import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { Quantity } from '../../imports/k8s';

/**
 * KGatewayMCPServersChart deploys MCP servers for use with kgateway
 * These servers provide various AI tool capabilities through the MCP protocol
 */
export class KGatewayMCPServersChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const namespace = 'mcp-servers';

    // Create ExternalSecret for GitHub token
    new ApiObject(this, 'github-token-secret', {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: {
        name: 'github-token',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-servers',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-50',
        },
      },
      spec: {
        refreshInterval: '1h',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: 'ClusterSecretStore',
        },
        target: {
          name: 'github-token',
          creationPolicy: 'Owner',
        },
        dataFrom: [
          {
            find: {
              name: {
                regexp: '^GITHUB-PAT$',
              },
            },
            rewrite: [
              {
                regexp: {
                  source: '^GITHUB-PAT$',
                  target: 'token',
                },
              },
            ],
          },
        ],
      },
    });

    // Grafana MCP Server - Provides Grafana dashboard and data source management
    new k8s.KubeDeployment(this, 'grafana-mcp-deployment', {
      metadata: {
        name: 'grafana-mcp',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'grafana-mcp',
          'app.kubernetes.io/component': 'mcp-server',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/enabled': 'true',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '10',
        },
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': 'grafana-mcp',
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': 'grafana-mcp',
              'app.kubernetes.io/component': 'mcp-server',
              'mcp.kgateway.dev/server': 'true',
            },
            annotations: {
              'prometheus.io/scrape': 'true',
              'prometheus.io/port': '9090',
              'prometheus.io/path': '/metrics',
            },
          },
          spec: {
            containers: [{
              name: 'grafana-mcp',
              image: 'hashicorp/http-echo:latest', // Temporary test image
              args: [
                '-text=grafana-mcp-test',
                '-listen=:8080',
              ],
              env: [
                {
                  name: 'GRAFANA_URL',
                  value: 'http://grafana.monitoring.svc.cluster.local:80',
                },
                {
                  name: 'GRAFANA_API_KEY',
                  valueFrom: {
                    secretKeyRef: {
                      name: 'grafana-api-key',
                      key: 'api-key',
                      optional: true,
                    },
                  },
                },
                {
                  name: 'LOG_LEVEL',
                  value: 'info',
                },
              ],
              ports: [{
                name: 'http',
                containerPort: 8080,
                protocol: 'TCP',
              }, {
                name: 'metrics',
                containerPort: 9090,
                protocol: 'TCP',
              }],
              resources: {
                requests: {
                  cpu: Quantity.fromString('100m'),
                  memory: Quantity.fromString('128Mi'),
                },
                limits: {
                  cpu: Quantity.fromString('500m'),
                  memory: Quantity.fromString('256Mi'),
                },
              },
              livenessProbe: {
                httpGet: {
                  path: '/health',
                  port: k8s.IntOrString.fromNumber(8080),
                },
                initialDelaySeconds: 10,
                periodSeconds: 30,
              },
              readinessProbe: {
                httpGet: {
                  path: '/health',
                  port: k8s.IntOrString.fromNumber(8080),
                },
                initialDelaySeconds: 5,
                periodSeconds: 10,
              },
              securityContext: {
                allowPrivilegeEscalation: false,
                capabilities: {
                  drop: ['ALL'],
                },
                readOnlyRootFilesystem: true,
                runAsNonRoot: true,
                runAsUser: 10001,
              },
            }],
            securityContext: {
              fsGroup: 10001,
              runAsNonRoot: true,
              seccompProfile: {
                type: 'RuntimeDefault',
              },
            },
          },
        },
      },
    });

    // Grafana MCP Service
    new k8s.KubeService(this, 'grafana-mcp-service', {
      metadata: {
        name: 'grafana-mcp',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'grafana-mcp',
          'app.kubernetes.io/component': 'mcp-server',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/enabled': 'true',  // Enable dynamic discovery
        },
        annotations: {
          'mcp.kgateway.dev/tools': 'grafana_*',
          'mcp.kgateway.dev/discovery': 'enabled',
          'mcp.kgateway.dev/description': 'Grafana dashboard and data source management',
          'kgateway.dev/mcp-path': '/mcp',  // Optional: customize MCP endpoint path
          'argocd.argoproj.io/sync-wave': '11',
        },
      },
      spec: {
        selector: {
          'app.kubernetes.io/name': 'grafana-mcp',
        },
        type: 'ClusterIP',
        ports: [{
          name: 'http',
          protocol: 'TCP',
          port: 8080,
          targetPort: k8s.IntOrString.fromNumber(8080),
          appProtocol: 'kgateway.dev/mcp',
        }, {
          name: 'metrics',
          protocol: 'TCP',
          port: 9090,
          targetPort: k8s.IntOrString.fromNumber(9090),
        }],
      },
    });

    // Echo MCP Server - Test server for validation
    new k8s.KubeDeployment(this, 'echo-mcp-deployment', {
      metadata: {
        name: 'echo-mcp',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'echo-mcp',
          'app.kubernetes.io/component': 'mcp-server',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/enabled': 'true',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '10',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': 'echo-mcp',
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': 'echo-mcp',
              'app.kubernetes.io/component': 'mcp-server',
              'mcp.kgateway.dev/server': 'true',
            },
          },
          spec: {
            containers: [{
              name: 'echo-mcp',
              image: 'hashicorp/http-echo:latest', // Temporary test image
              args: [
                '-text=test-server',
                '-listen=:8080',
              ],
              ports: [{
                name: 'http',
                containerPort: 8080,
                protocol: 'TCP',
              }],
              resources: {
                requests: {
                  cpu: Quantity.fromString('50m'),
                  memory: Quantity.fromString('64Mi'),
                },
                limits: {
                  cpu: Quantity.fromString('200m'),
                  memory: Quantity.fromString('128Mi'),
                },
              },
              livenessProbe: {
                httpGet: {
                  path: '/health',
                  port: k8s.IntOrString.fromNumber(8080),
                },
                initialDelaySeconds: 5,
                periodSeconds: 10,
              },
              securityContext: {
                allowPrivilegeEscalation: false,
                capabilities: {
                  drop: ['ALL'],
                },
                readOnlyRootFilesystem: true,
                runAsNonRoot: true,
                runAsUser: 10001,
              },
            }],
            securityContext: {
              fsGroup: 10001,
              runAsNonRoot: true,
              seccompProfile: {
                type: 'RuntimeDefault',
              },
            },
          },
        },
      },
    });

    // Echo MCP Service
    new k8s.KubeService(this, 'echo-mcp-service', {
      metadata: {
        name: 'echo-mcp',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'echo-mcp',
          'app.kubernetes.io/component': 'mcp-server',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/enabled': 'true',  // Enable dynamic discovery
        },
        annotations: {
          'mcp.kgateway.dev/tools': 'echo',
          'mcp.kgateway.dev/discovery': 'enabled',
          'mcp.kgateway.dev/description': 'Echo test server for MCP validation',
          'argocd.argoproj.io/sync-wave': '11',
        },
      },
      spec: {
        selector: {
          'app.kubernetes.io/name': 'echo-mcp',
        },
        type: 'ClusterIP',
        ports: [{
          name: 'http',
          protocol: 'TCP',
          port: 8080,
          targetPort: k8s.IntOrString.fromNumber(8080),
          appProtocol: 'kgateway.dev/mcp',
        }],
      },
    });

    // Text Tools MCP Server - Text manipulation utilities
    new k8s.KubeDeployment(this, 'text-tools-mcp-deployment', {
      metadata: {
        name: 'text-tools-mcp',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'text-tools-mcp',
          'app.kubernetes.io/component': 'mcp-server',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/enabled': 'true',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '10',
        },
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': 'text-tools-mcp',
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': 'text-tools-mcp',
              'app.kubernetes.io/component': 'mcp-server',
              'mcp.kgateway.dev/server': 'true',
            },
          },
          spec: {
            containers: [{
              name: 'text-tools',
              image: 'hashicorp/http-echo:latest', // Temporary test image
              args: [
                '-text=test-server',
                '-listen=:8080',
              ],
              ports: [{
                name: 'http',
                containerPort: 8080,
                protocol: 'TCP',
              }],
              resources: {
                requests: {
                  cpu: Quantity.fromString('100m'),
                  memory: Quantity.fromString('128Mi'),
                },
                limits: {
                  cpu: Quantity.fromString('500m'),
                  memory: Quantity.fromString('256Mi'),
                },
              },
              livenessProbe: {
                httpGet: {
                  path: '/health',
                  port: k8s.IntOrString.fromNumber(8080),
                },
                initialDelaySeconds: 5,
                periodSeconds: 10,
              },
              securityContext: {
                allowPrivilegeEscalation: false,
                capabilities: {
                  drop: ['ALL'],
                },
                readOnlyRootFilesystem: true,
                runAsNonRoot: true,
                runAsUser: 10001,
              },
            }],
            securityContext: {
              fsGroup: 10001,
              runAsNonRoot: true,
              seccompProfile: {
                type: 'RuntimeDefault',
              },
            },
          },
        },
      },
    });

    // Text Tools MCP Service
    new k8s.KubeService(this, 'text-tools-mcp-service', {
      metadata: {
        name: 'text-tools-mcp',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'text-tools-mcp',
          'app.kubernetes.io/component': 'mcp-server',
          'app.kubernetes.io/part-of': 'kgateway',
          'mcp.kgateway.dev/enabled': 'true',  // Enable dynamic discovery
        },
        annotations: {
          'mcp.kgateway.dev/tools': 'text_*',
          'mcp.kgateway.dev/discovery': 'enabled',
          'mcp.kgateway.dev/description': 'Text manipulation and processing tools',
          'argocd.argoproj.io/sync-wave': '11',
        },
      },
      spec: {
        selector: {
          'app.kubernetes.io/name': 'text-tools-mcp',
        },
        type: 'ClusterIP',
        ports: [{
          name: 'http',
          protocol: 'TCP',
          port: 8080,
          targetPort: k8s.IntOrString.fromNumber(8080),
          appProtocol: 'kgateway.dev/mcp',
        }],
      },
    });

    // Create ReferenceGrant to allow HTTPRoute to reference services
    new ApiObject(this, 'mcp-servers-reference-grant', {
      apiVersion: 'gateway.networking.k8s.io/v1beta1',
      kind: 'ReferenceGrant',
      metadata: {
        name: 'allow-kgateway-routes',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-servers',
          'app.kubernetes.io/component': 'reference-grant',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '5',
        },
      },
      spec: {
        from: [
          {
            group: 'gateway.networking.k8s.io',
            kind: 'HTTPRoute',
            namespace: namespace,
          },
          {
            group: 'gateway.networking.k8s.io',
            kind: 'HTTPRoute',
            namespace: 'kgateway-system',
          },
          {
            group: 'gateway.networking.k8s.io',
            kind: 'GRPCRoute',
            namespace: namespace,
          },
          {
            group: 'gateway.networking.k8s.io',
            kind: 'GRPCRoute',
            namespace: 'kgateway-system',
          },
        ],
        to: [
          {
            group: '',
            kind: 'Service',
          },
        ],
      },
    });

    // Create NetworkPolicy to allow ingress from kgateway
    new k8s.KubeNetworkPolicy(this, 'mcp-servers-network-policy', {
      metadata: {
        name: 'allow-kgateway-ingress',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'mcp-servers',
          'app.kubernetes.io/component': 'network-policy',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '5',
        },
      },
      spec: {
        podSelector: {
          matchLabels: {
            'mcp.kgateway.dev/server': 'true',
          },
        },
        policyTypes: ['Ingress'],
        ingress: [
          {
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    'app.kubernetes.io/name': 'kgateway',
                  },
                },
              },
              {
                podSelector: {
                  matchLabels: {
                    'gateway.kgateway.dev/proxy': 'true',
                  },
                },
              },
            ],
            ports: [
              {
                port: k8s.IntOrString.fromNumber(8080),
                protocol: 'TCP',
              },
            ],
          },
          {
            // Allow metrics scraping from monitoring namespace
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    'name': 'monitoring',
                  },
                },
              },
            ],
            ports: [
              {
                port: k8s.IntOrString.fromNumber(9090),
                protocol: 'TCP',
              },
            ],
          },
        ],
      },
    });
  }
}