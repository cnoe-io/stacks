/**
 * KagentChart - Deploys kagent platform components (CRDs, controller, engine, dashboard)
 *
 * This chart creates the core kagent infrastructure:
 * - Namespace
 * - CRDs (Agent, ModelConfig, MCPServer, Memory, RemoteMCPServer, ToolServer)
 * - ServiceAccounts and RBAC
 * - Controller Deployment
 * - Engine (App) Deployment
 * - Dashboard Deployment
 * - Services
 * - Ingress for dashboard
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { Agent, ModelConfig, McpServer, Memory, RemoteMcpServer, ToolServer } from '../../imports/kagent.dev';
import { createKagentSecurityContext, createKagentResourceLimits, kagentSyncWave } from '../../lib/kagent-helpers';

export class KagentChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const ns = 'kagent';
    const appName = 'kagent';

    // Namespace
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: ns,
        annotations: kagentSyncWave(-100),
      },
    });

    // Note: CRDs are deployed via separate kagent-crds Helm chart or kubectl apply
    // We don't synthesize them here as they're large and managed by upstream
    // Instead, we assume they exist when this chart is applied

    // ServiceAccount for kagent controller
    const controllerSA = new k8s.KubeServiceAccount(this, 'controller-sa', {
      metadata: {
        name: `${appName}-controller`,
        namespace: ns,
        annotations: kagentSyncWave(-90),
      },
    });

    // ClusterRole for kagent controller
    const controllerRole = new k8s.KubeClusterRole(this, 'controller-role', {
      metadata: {
        name: `${appName}-controller`,
        annotations: kagentSyncWave(-90),
      },
      rules: [
        {
          apiGroups: ['kagent.dev'],
          resources: ['agents', 'agents/status', 'agents/finalizers'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: ['kagent.dev'],
          resources: ['modelconfigs', 'modelconfigs/status'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['kagent.dev'],
          resources: ['mcpservers', 'mcpservers/status'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['kagent.dev'],
          resources: ['remotemcpservers', 'remotemcpservers/status', 'toolservers', 'toolservers/status'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: [''],
          resources: ['pods', 'pods/log', 'pods/status'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: [''],
          resources: ['services'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'deployments/status'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: [''],
          resources: ['configmaps'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // ClusterRoleBinding for controller
    new k8s.KubeClusterRoleBinding(this, 'controller-rolebinding', {
      metadata: {
        name: `${appName}-controller`,
        annotations: kagentSyncWave(-90),
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: controllerRole.name,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: controllerSA.name,
          namespace: ns,
        },
      ],
    });

    // ServiceAccount for kagent tools (built-in K8s tools)
    const toolsSA = new k8s.KubeServiceAccount(this, 'tools-sa', {
      metadata: {
        name: `${appName}-tools`,
        namespace: ns,
        annotations: kagentSyncWave(-90),
      },
    });

    // ClusterRole for tools (read-only K8s access)
    const toolsRole = new k8s.KubeClusterRole(this, 'tools-role', {
      metadata: {
        name: `${appName}-tools-read`,
        annotations: kagentSyncWave(-90),
      },
      rules: [
        {
          apiGroups: ['', 'apps', 'batch', 'networking.k8s.io'],
          resources: ['*'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['apiextensions.k8s.io'],
          resources: ['customresourcedefinitions'],
          verbs: ['get', 'list'],
        },
      ],
    });

    // ClusterRoleBinding for tools
    new k8s.KubeClusterRoleBinding(this, 'tools-rolebinding', {
      metadata: {
        name: `${appName}-tools-read`,
        annotations: kagentSyncWave(-90),
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: toolsRole.name,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: toolsSA.name,
          namespace: ns,
        },
      ],
    });

    // Controller Deployment
    new k8s.KubeDeployment(this, 'controller-deployment', {
      metadata: {
        name: `${appName}-controller`,
        namespace: ns,
        annotations: kagentSyncWave(0),
        labels: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'controller',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': appName,
            'app.kubernetes.io/component': 'controller',
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': appName,
              'app.kubernetes.io/component': 'controller',
            },
          },
          spec: {
            serviceAccountName: controllerSA.name,
            securityContext: {},
            volumes: [
              {
                name: 'sqlite-volume',
                emptyDir: {
                  sizeLimit: k8s.Quantity.fromString('500Mi'),
                  medium: 'Memory',
                },
              },
            ],
            containers: [
              {
                name: 'controller',
                image: 'ghcr.io/kagent-dev/kagent/controller:0.6.3',
                args: [
                  '-default-model-config-name',
                  'default-model-config',
                  '-zap-log-level',
                  'info',
                  '-watch-namespaces',
                  '',
                  '-database-type',
                  'sqlite',
                  '-sqlite-database-path',
                  '/sqlite-volume/kagent.db',
                ],
                ports: [
                  { name: 'http', containerPort: 8083, protocol: 'TCP' },
                  { name: 'metrics', containerPort: 8080, protocol: 'TCP' },
                ],
                resources: createKagentResourceLimits('controller'),
                volumeMounts: [
                  {
                    name: 'sqlite-volume',
                    mountPath: '/sqlite-volume',
                  },
                ],
                env: [
                  {
                    name: 'KAGENT_NAMESPACE',
                    valueFrom: {
                      fieldRef: {
                        fieldPath: 'metadata.namespace',
                      },
                    },
                  },
                ],
              },
            ],
          },
        },
      },
    });

    // Controller Service (for A2A protocol)
    new k8s.KubeService(this, 'controller-service', {
      metadata: {
        name: `${appName}-controller`,
        namespace: ns,
        annotations: kagentSyncWave(0),
        labels: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'controller',
        },
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 8083,
            targetPort: k8s.IntOrString.fromNumber(8083),
            protocol: 'TCP',
          },
          {
            name: 'metrics',
            port: 8080,
            targetPort: k8s.IntOrString.fromNumber(8080),
            protocol: 'TCP',
          },
        ],
        selector: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'controller',
        },
      },
    });

    // Dashboard Deployment
    new k8s.KubeDeployment(this, 'dashboard-deployment', {
      metadata: {
        name: `${appName}-dashboard`,
        namespace: ns,
        annotations: kagentSyncWave(0),
        labels: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'dashboard',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': appName,
            'app.kubernetes.io/component': 'dashboard',
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': appName,
              'app.kubernetes.io/component': 'dashboard',
            },
          },
          spec: {
            securityContext: {},
            containers: [
              {
                name: 'dashboard',
                image: 'cr.kagent.dev/kagent-dev/kagent/ui:0.6.3',
                ports: [{ name: 'http', containerPort: 8080, protocol: 'TCP' }],
                resources: createKagentResourceLimits('dashboard'),
                env: [
                  {
                    name: 'NEXT_PUBLIC_BACKEND_URL',
                    value: `http://${appName}-controller.${ns}.svc.cluster.local:8083/api`,
                  },
                ],
              },
            ],
          },
        },
      },
    });

    // Dashboard Service
    new k8s.KubeService(this, 'dashboard-service', {
      metadata: {
        name: `${appName}-dashboard`,
        namespace: ns,
        annotations: kagentSyncWave(0),
        labels: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'dashboard',
        },
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 8082,
            targetPort: k8s.IntOrString.fromNumber(8080),
            protocol: 'TCP',
          },
        ],
        selector: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'dashboard',
        },
      },
    });

    // Dashboard Ingress (domain-based routing - CNOE standard)
    // Note: Uses subdomain routing (kagent.cnoe.localtest.me) instead of path-based
    // because Next.js requires basePath configuration for path-based routing
    new k8s.KubeIngress(this, 'dashboard-ingress', {
      metadata: {
        name: `${appName}-dashboard`,
        namespace: ns,
        annotations: kagentSyncWave(100),
        labels: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'dashboard',
        },
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [
          {
            host: 'kagent.cnoe.localtest.me',
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: `${appName}-dashboard`,
                      port: {
                        number: 8082,
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

    // Tool Server Deployment (built-in K8s tools)
    new k8s.KubeDeployment(this, 'tools-deployment', {
      metadata: {
        name: `${appName}-tools`,
        namespace: ns,
        annotations: kagentSyncWave(0),
        labels: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'tool-server',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': appName,
            'app.kubernetes.io/component': 'tool-server',
          },
        },
        template: {
          metadata: {
            labels: {
              'app.kubernetes.io/name': appName,
              'app.kubernetes.io/component': 'tool-server',
            },
          },
          spec: {
            serviceAccountName: toolsSA.name,
            securityContext: {},
            containers: [
              {
                name: 'tools',
                image: 'ghcr.io/kagent-dev/kagent/tools:0.0.12',
                ports: [{ name: 'http', containerPort: 3000, protocol: 'TCP' }],
                resources: createKagentResourceLimits('mcp-server'),
                env: [
                  {
                    name: 'KUBERNETES_NAMESPACE',
                    valueFrom: {
                      fieldRef: {
                        fieldPath: 'metadata.namespace',
                      },
                    },
                  },
                ],
              },
            ],
          },
        },
      },
    });

    // Tool Server Service
    new k8s.KubeService(this, 'tools-service', {
      metadata: {
        name: `${appName}-tools`,
        namespace: ns,
        annotations: kagentSyncWave(0),
        labels: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'tool-server',
        },
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 3000,
            targetPort: k8s.IntOrString.fromNumber(3000),
            protocol: 'TCP',
          },
        ],
        selector: {
          'app.kubernetes.io/name': appName,
          'app.kubernetes.io/component': 'tool-server',
        },
      },
    });

    // RemoteMCPServer resource for kagent-tools (makes built-in K8s tools available to agents)
    new RemoteMcpServer(this, 'kagent-tool-server', {
      metadata: {
        name: 'kagent-tool-server',
        namespace: ns,
        annotations: kagentSyncWave(50),
        labels: {
          'app.kubernetes.io/name': 'kagent-tool-server',
          'app.kubernetes.io/component': 'remote-mcp-server',
        },
      },
      spec: {
        description: 'Built-in Kubernetes tools for agent use',
        url: `http://${appName}-tools.${ns}.svc.cluster.local:3000/mcp`,
      },
    });
  }
}
