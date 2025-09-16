import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

/**
 * KGatewayGatewayClassChart creates the GatewayClass resource for kgateway
 * This enables kgateway to manage Gateway API resources
 */
export class KGatewayGatewayClassChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const namespace = 'kgateway-system';

    // Create GatewayClass for kgateway
    new ApiObject(this, 'gatewayclass', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'GatewayClass',
      metadata: {
        name: 'kgateway',
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'gatewayclass',
          'app.kubernetes.io/part-of': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-80',
          'gateway.kgateway.dev/description': 'KGateway controller for AI and MCP workloads',
        },
      },
      spec: {
        controllerName: 'kgateway.dev/kgateway',
        description: 'KGateway - Enterprise-grade AI Gateway with MCP support',
        parametersRef: {
          group: 'gateway.kgateway.dev',
          kind: 'GatewayParameters',
          name: 'default-gateway-params',
          namespace: namespace,
        },
      },
    });

    // Create default GatewayParameters
    new ApiObject(this, 'gateway-parameters', {
      apiVersion: 'gateway.kgateway.dev/v1alpha1',
      kind: 'GatewayParameters',
      metadata: {
        name: 'default-gateway-params',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'parameters',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-81',
        },
      },
      spec: {
        // Use kube mode for Kubernetes deployment
        kube: {
          agentGateway: {
            enabled: true,
            logLevel: 'info',
            image: {
              tag: '0.8.3',
            },
          },
          // Deployment configuration
          deployment: {
            replicas: 2,
          },
          // Service configuration
          service: {
            type: 'LoadBalancer',
            ports: [
              {
                port: 80,
              },
              {
                port: 443,
              },
            ],
            extraAnnotations: {
              'service.beta.kubernetes.io/azure-load-balancer-internal': 'true',
            },
          },
          // Pod template configuration
          podTemplate: {
            extraLabels: {
              'app.kubernetes.io/managed-by': 'kgateway',
              'gateway.kgateway.dev/proxy': 'true',
            },
            extraAnnotations: {
              'prometheus.io/scrape': 'true',
              'prometheus.io/port': '9090',
              'prometheus.io/path': '/metrics',
            },
          },
          // Envoy container configuration
          envoyContainer: {
            image: {
              repository: 'docker.io/envoyproxy/envoy',  // Use full Docker Hub path
              tag: 'v1.33.0',
              pullPolicy: 'IfNotPresent',
            },
            resources: {
              requests: {
                cpu: '200m',
                memory: '256Mi',
              },
              limits: {
                cpu: '1000m',
                memory: '1Gi',
              },
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
          },
          // AI extension configuration for MCP support
          aiExtension: {
            enabled: true,
            image: {
              repository: 'cr.kgateway.dev/kgateway-dev/ai-extension',  // Use full registry path
              tag: 'v2.0.4',
              pullPolicy: 'IfNotPresent',
            },
            env: [
              {
                name: 'LOG_LEVEL',
                value: 'info',
              },
              {
                name: 'LOG_FORMAT',
                value: 'json',
              },
            ],
          },
        },
      },
    });

    // Create ServiceAccount for gateway proxies
    new ApiObject(this, 'proxy-service-account', {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: {
        name: 'kgateway-proxy',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'proxy',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-85',
        },
      },
    });

    // Create ClusterRole for gateway proxies
    new ApiObject(this, 'proxy-cluster-role', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: {
        name: 'kgateway-proxy',
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'proxy',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-84',
        },
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['services', 'endpoints', 'secrets'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['gateway.networking.k8s.io'],
          resources: ['httproutes', 'grpcroutes', 'gateways'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['gateway.kgateway.dev'],
          resources: ['*'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // Create ClusterRoleBinding for gateway proxies
    new ApiObject(this, 'proxy-cluster-role-binding', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        name: 'kgateway-proxy',
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'proxy',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-83',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'kgateway-proxy',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'kgateway-proxy',
          namespace: namespace,
        },
      ],
    });

    // Create AgentGateway GatewayClass for MCP support
    new ApiObject(this, 'agentgateway-class', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'GatewayClass',
      metadata: {
        name: 'agentgateway',
        labels: {
          'app.kubernetes.io/name': 'agentgateway',
          'app.kubernetes.io/component': 'gatewayclass',
          'app.kubernetes.io/part-of': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-80',
          'gateway.kgateway.dev/description': 'AgentGateway controller for MCP protocol support',
        },
      },
      spec: {
        controllerName: 'kgateway.dev/kgateway',  // Use the same controller as kgateway
        description: 'AgentGateway - MCP protocol support with dynamic discovery',
        parametersRef: {
          group: 'gateway.kgateway.dev',
          kind: 'GatewayParameters',
          name: 'agentgateway-params',
          namespace: namespace,
        },
      },
    });

    // Create GatewayParameters for AgentGateway
    new ApiObject(this, 'agentgateway-parameters', {
      apiVersion: 'gateway.kgateway.dev/v1alpha1',
      kind: 'GatewayParameters',
      metadata: {
        name: 'agentgateway-params',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'agentgateway',
          'app.kubernetes.io/component': 'parameters',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-81',
        },
      },
      spec: {
        // Use kube mode for Kubernetes deployment
        kube: {
          agentGateway: {
            enabled: true,
            logLevel: 'info',
            image: {
              tag: '0.8.3',
            },
          },
          // Deployment configuration
          deployment: {
            replicas: 2,
          },
          // Service configuration
          service: {
            type: 'LoadBalancer', // Use LoadBalancer for AgentGateway
            ports: [
              {
                port: 8080,
              },
            ],
            extraAnnotations: {
              'service.beta.kubernetes.io/azure-load-balancer-internal': 'true',
            },
          },
          // Pod template configuration
          podTemplate: {
            extraLabels: {
              'app.kubernetes.io/managed-by': 'agentgateway',
              'gateway.kgateway.dev/proxy': 'true',
              'gateway.kgateway.dev/type': 'agentgateway',
            },
            extraAnnotations: {
              'prometheus.io/scrape': 'true',
              'prometheus.io/port': '9090',
              'prometheus.io/path': '/metrics',
            },
          },
          // Envoy container configuration
          envoyContainer: {
            image: {
              repository: 'docker.io/envoyproxy/envoy',  // Use full Docker Hub path
              tag: 'v1.33.0',
              pullPolicy: 'IfNotPresent',
            },
            resources: {
              requests: {
                cpu: '200m',
                memory: '256Mi',
              },
              limits: {
                cpu: '1000m',
                memory: '1Gi',
              },
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
          },
          // AI extension configuration for MCP support - required for AgentGateway
          aiExtension: {
            enabled: true,
            image: {
              repository: 'cr.kgateway.dev/kgateway-dev/ai-extension',  // Use full registry path
              tag: 'v2.1.0-main',
              pullPolicy: 'IfNotPresent',
            },
            env: [
              {
                name: 'LOG_LEVEL',
                value: 'info',
              },
              {
                name: 'LOG_FORMAT',
                value: 'json',
              },
              {
                name: 'MCP_DISCOVERY_ENABLED',
                value: 'true',
              },
              {
                name: 'MCP_PROTOCOL_SUPPORT',
                value: 'sse,http',
              },
            ],
          },
        },
      },
    });
  }
}
