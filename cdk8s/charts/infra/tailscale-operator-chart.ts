import { Chart, ChartProps, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  ProxyGroup,
  ProxyGroupSpecType,
  ProxyGroupSpecKubeApiServerMode
} from '../../imports/tailscale.com';
import { createEnvExternalSecret } from '../../lib/eso-helpers';
import { ExternalSecretSpecSecretStoreRefKind } from '../../imports/external-secrets.io';

/**
 * Impersonation grant mapping Tailscale groups to Kubernetes groups
 */
export interface ImpersonationGrant {
  /**
   * Tailscale group name (e.g., 'group:admins')
   */
  tailscaleGroup: string;

  /**
   * Kubernetes groups for impersonation (e.g., ['system:masters'])
   */
  kubernetesGroups: string[];

  /**
   * Human-readable description of grant purpose
   */
  description?: string;
}

/**
 * Configuration properties for TailscaleOperatorChart
 */
export interface TailscaleOperatorChartProps extends ChartProps {
  /**
   * Target environment determining HA and resource allocation
   */
  environmentName: 'dev' | 'staging' | 'production';

  /**
   * Cluster identifier used in operator naming
   */
  clusterName: string;

  /**
   * Name of Kubernetes Secret containing OAuth credentials
   * @default 'tailscale-oauth'
   */
  oauthSecretName?: string;

  /**
   * Kubernetes namespace for operator deployment
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Enable high-availability ProxyGroup (requires Tailscale Services alpha)
   * @default false
   */
  enableHA?: boolean;

  /**
   * Number of proxy replicas when HA enabled
   * @default 2
   */
  proxyReplicas?: number;

  /**
   * Container image for operator deployment
   * @default 'tailscale/k8s-operator:v1.88.3'
   */
  operatorImage?: string;

  /**
   * Tailscale group to Kubernetes group mappings
   * @default []
   */
  impersonationGrants?: ImpersonationGrant[];
}

/**
 * Chart for deploying Tailscale Kubernetes Operator
 *
 * Enables secure remote access to Kubernetes API server via Tailscale network
 * with identity-based access control through Tailscale group impersonation.
 */
export class TailscaleOperatorChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleOperatorChartProps) {
    super(scope, id, props);

    // Apply defaults
    const namespace = props.namespace || 'tailscale';
    const oauthSecretName = props.oauthSecretName || 'tailscale-oauth';
    const operatorImage = props.operatorImage || 'tailscale/k8s-operator:v1.88.3';
    const proxyReplicas = props.proxyReplicas || 2;
    const impersonationGrants = props.impersonationGrants || [];

    // Validate configuration
    if (props.enableHA && proxyReplicas < 2) {
      throw new Error('HA mode requires at least 2 proxy replicas');
    }

    // T010: Create Namespace
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100',
        },
      },
    });

    // T011: Create ServiceAccount
    new k8s.KubeServiceAccount(this, 'operator-sa', {
      metadata: {
        name: 'operator',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
    });

    // T012: Create ExternalSecret for OAuth credentials
    const oauthSecret = createEnvExternalSecret(this, 'tailscale-oauth-external', {
      externalName: oauthSecretName,
      name: oauthSecretName,
      namespace: namespace,
      secretStoreRef: {
        name: 'azure-keyvault-store',
        kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
      },
      mappings: [
        { key: 'clientId', remoteRef: { key: 'TAILSCALE-OAUTH-CLIENT-ID' } },
        { key: 'clientSecret', remoteRef: { key: 'TAILSCALE-OAUTH-CLIENT-SECRET' } }
      ]
    });
    oauthSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', {
      'argocd.argoproj.io/sync-wave': '-80'
    }));

    // T013: Create ClusterRole
    new k8s.KubeClusterRole(this, 'operator-clusterrole', {
      metadata: {
        name: 'tailscale-operator',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      rules: [
        {
          apiGroups: ['tailscale.com'],
          resources: ['proxygroups', 'connectors', 'dnsconfigs', 'proxyclasses', 'recorders'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: [''],
          resources: ['secrets', 'services', 'configmaps', 'serviceaccounts'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete', 'deletecollection'],
        },
        {
          apiGroups: [''],
          resources: ['services/status'],
          verbs: ['update', 'patch'],
        },
        {
          apiGroups: [''],
          resources: ['pods', 'nodes'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'statefulsets'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete', 'deletecollection'],
        },
        // RBAC permissions (needed for creating ServiceAccounts and RoleBindings for proxies)
        {
          apiGroups: ['rbac.authorization.k8s.io'],
          resources: ['roles', 'rolebindings'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        // Ingress permissions (required for LoadBalancer service exposure)
        {
          apiGroups: ['networking.k8s.io'],
          resources: ['ingresses'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        // EndpointSlice permissions (required for service discovery)
        {
          apiGroups: ['discovery.k8s.io'],
          resources: ['endpointslices'],
          verbs: ['get', 'list', 'watch'],
        },
        // CRD permissions (required for checking installed CRDs)
        {
          apiGroups: ['apiextensions.k8s.io'],
          resources: ['customresourcedefinitions'],
          verbs: ['get', 'list', 'watch'],
        },
        // API server proxy impersonation permissions (required for auth mode)
        {
          apiGroups: [''],
          resources: ['users', 'groups'],
          verbs: ['impersonate'],
        },
        {
          apiGroups: ['authentication.k8s.io'],
          resources: ['userextras/accesskeyid', 'userextras/arn', 'userextras/canonicalarn', 'userextras/sessionname'],
          verbs: ['impersonate'],
        },
      ],
    });

    // T014: Create ClusterRoleBinding
    new k8s.KubeClusterRoleBinding(this, 'operator-clusterrolebinding', {
      metadata: {
        name: 'tailscale-operator',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'tailscale-operator',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'operator',
          namespace: namespace,
        },
      ],
    });

    // T015-T017: Create operator Deployment
    // Sync wave -70 ensures ExternalSecret (wave -80) creates the secret first
    new k8s.KubeDeployment(this, 'operator-deployment', {
      metadata: {
        name: 'tailscale-operator',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'tailscale-operator',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'tailscale-operator',
            },
          },
          spec: {
            serviceAccountName: 'operator',
            containers: [
              {
                name: 'operator',
                image: operatorImage,
                env: [
                  {
                    name: 'OPERATOR_INITIAL_TAGS',
                    value: 'tag:k8s-operator',
                  },
                  {
                    name: 'OPERATOR_HOSTNAME',
                    value: `${props.clusterName}-operator`,
                  },
                  {
                    name: 'CLIENT_ID_FILE',
                    value: '/oauth/client-id',
                  },
                  {
                    name: 'CLIENT_SECRET_FILE',
                    value: '/oauth/client-secret',
                  },
                  {
                    name: 'OPERATOR_NAMESPACE',
                    value: namespace,
                  },
                  {
                    name: 'APISERVER_PROXY',
                    value: 'true', // Enable in-process API server proxy with auth
                  },
                  {
                    name: 'OPERATOR_LOGGING',
                    value: 'debug', // Enable debug logging to troubleshoot API proxy
                  },
                ],
                volumeMounts: [
                  {
                    name: 'oauth',
                    mountPath: '/oauth',
                    readOnly: true,
                  },
                ],
              },
            ],
            volumes: [
              {
                name: 'oauth',
                secret: {
                  secretName: oauthSecretName,
                  items: [
                    {
                      key: 'clientId',
                      path: 'client-id',
                    },
                    {
                      key: 'clientSecret',
                      path: 'client-secret',
                    },
                  ],
                },
              },
            ],
          },
        },
      },
    });

    // User Story 3: ProxyGroup for HA (only if enabled)
    if (props.enableHA || ['staging', 'production'].includes(props.environmentName)) {
      new ProxyGroup(this, 'api-server-proxy', {
        metadata: {
          name: `${props.clusterName}-api-server`,
          namespace: namespace,
          annotations: {
            'argocd.argoproj.io/sync-wave': '0',
          },
        },
        spec: {
          type: ProxyGroupSpecType.KUBE_HYPHEN_APISERVER,
          replicas: proxyReplicas,
          tags: ['tag:k8s'],
          kubeApiServer: {
            mode: ProxyGroupSpecKubeApiServerMode.AUTH,
          },
        },
      });
    }
  }
}
