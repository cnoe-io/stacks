import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * KGatewayNamespaceChart creates the namespace and RBAC resources for kgateway
 * This is deployed in the host cluster as a central resource
 */
export class KGatewayNamespaceChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const namespace = 'kgateway-system';

    // Create the kgateway-system namespace
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespace,
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'infrastructure',
          'app.kubernetes.io/part-of': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
          // Allow pods from vclusters to access services in this namespace
          'pod-security.kubernetes.io/enforce': 'baseline',
          'pod-security.kubernetes.io/warn': 'restricted',
          'pod-security.kubernetes.io/audit': 'restricted',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100',
        },
      },
    });

    // Create ServiceAccount for kgateway components
    new k8s.KubeServiceAccount(this, 'kgateway-sa', {
      metadata: {
        name: 'kgateway-controller',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'controller',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
    });

    // Create ClusterRole for kgateway controller
    new k8s.KubeClusterRole(this, 'kgateway-controller-role', {
      metadata: {
        name: 'kgateway-controller',
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'controller',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      rules: [
        // Gateway API resources
        {
          apiGroups: ['gateway.networking.k8s.io'],
          resources: [
            'gateways',
            'gatewayclasses',
            'httproutes',
            'grpcroutes',
            'referencegrants',
            'tcproutes',
            'tlsroutes',
            'udproutes',
          ],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['gateway.networking.k8s.io'],
          resources: [
            'gateways/status',
            'gatewayclasses/status',
            'httproutes/status',
            'grpcroutes/status',
            'tcproutes/status',
            'tlsroutes/status',
            'udproutes/status',
          ],
          verbs: ['get', 'update', 'patch'],
        },
        // KGateway CRDs
        {
          apiGroups: ['gateway.kgateway.dev'],
          resources: ['*'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        // Core resources
        {
          apiGroups: [''],
          resources: [
            'services',
            'endpoints',
            'secrets',
            'configmaps',
            'namespaces',
          ],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: [''],
          resources: ['services/status'],
          verbs: ['get', 'update', 'patch'],
        },
        // Deployments for managing gateway proxies
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'daemonsets'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        // Events
        {
          apiGroups: [''],
          resources: ['events'],
          verbs: ['create', 'patch'],
        },
        // Coordination for leader election
        {
          apiGroups: ['coordination.k8s.io'],
          resources: ['leases'],
          verbs: ['get', 'list', 'create', 'update', 'patch', 'delete'],
        },
      ],
    });

    // Create ClusterRoleBinding
    new k8s.KubeClusterRoleBinding(this, 'kgateway-controller-binding', {
      metadata: {
        name: 'kgateway-controller',
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'controller',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-89',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'kgateway-controller',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'kgateway-controller',
          namespace: namespace,
        },
      ],
    });

    // Create Role for namespace-specific permissions
    new k8s.KubeRole(this, 'kgateway-namespace-role', {
      metadata: {
        name: 'kgateway-controller',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'controller',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['pods', 'services', 'endpoints', 'configmaps', 'secrets'],
          verbs: ['*'],
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'replicasets'],
          verbs: ['*'],
        },
      ],
    });

    // Create RoleBinding for namespace-specific permissions
    new k8s.KubeRoleBinding(this, 'kgateway-namespace-binding', {
      metadata: {
        name: 'kgateway-controller',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/component': 'controller',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-89',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'kgateway-controller',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'kgateway-controller',
          namespace: namespace,
        },
      ],
    });

    // Create namespace for MCP servers
    new k8s.KubeNamespace(this, 'mcp-servers-namespace', {
      metadata: {
        name: 'mcp-servers',
        labels: {
          'app.kubernetes.io/name': 'mcp-servers',
          'app.kubernetes.io/component': 'servers',
          'app.kubernetes.io/part-of': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100',
        },
      },
    });
  }
}