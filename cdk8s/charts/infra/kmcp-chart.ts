/**
 * KmcpChart - Deploys kmcp controller for managing MCPServer resources
 *
 * kmcp (Kubernetes MCP) is a controller that manages MCPServer custom resources.
 * It watches for MCPServer resources and creates corresponding Deployments/Services
 * to run MCP (Model Context Protocol) servers in the cluster.
 *
 * Note: MCPServer CRD is part of kagent.dev API group and deployed by KagentChart
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { createKagentSecurityContext, createKagentResourceLimits, kagentSyncWave } from '../../lib/kagent-helpers';

export class KmcpChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const ns = 'kagent';
    const appName = 'kmcp';

    // ServiceAccount for kmcp controller
    const controllerSA = new k8s.KubeServiceAccount(this, 'controller-sa', {
      metadata: {
        name: `${appName}-controller`,
        namespace: ns,
        annotations: kagentSyncWave(-90),
      },
    });

    // ClusterRole for kmcp controller
    const controllerRole = new k8s.KubeClusterRole(this, 'controller-role', {
      metadata: {
        name: `${appName}-controller`,
        annotations: kagentSyncWave(-90),
      },
      rules: [
        {
          apiGroups: ['kagent.dev'],
          resources: ['mcpservers', 'mcpservers/status', 'mcpservers/finalizers'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
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
          apiGroups: [''],
          resources: ['serviceaccounts'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'deployments/status'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: [''],
          resources: ['configmaps'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: [''],
          resources: ['secrets'],
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

    // kmcp Controller Deployment
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
            containers: [
              {
                name: 'controller',
                image: 'ghcr.io/kagent-dev/kmcp/controller:0.1.8',
                ports: [
                  { name: 'metrics', containerPort: 8080, protocol: 'TCP' },
                ],
                resources: createKagentResourceLimits('controller'),
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
  }
}
