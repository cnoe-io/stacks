import { Chart, ChartProps, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { createEnvExternalSecret } from '../../lib/eso-helpers';
import { ExternalSecretSpecSecretStoreRefKind } from '../../imports/external-secrets.io';

/**
 * Configuration properties for TailscaleApiProxyChart
 */
export interface TailscaleApiProxyChartProps extends ChartProps {
  /**
   * Cluster identifier used in proxy naming
   */
  clusterName: string;

  /**
   * Name of Kubernetes Secret containing Tailscale auth key
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Kubernetes namespace for proxy deployment
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Tailscale container image
   * @default 'tailscale/tailscale:latest'
   */
  tailscaleImage?: string;

  /**
   * kubectl container image
   * @default 'bitnami/kubectl:latest'
   */
  kubectlImage?: string;
}

/**
 * Chart for deploying Tailscale API Proxy using sidecar pattern
 *
 * Enables secure remote access to Kubernetes API server via Tailscale network
 * without requiring alpha features. Uses full Tailscale daemon + kubectl-proxy.
 */
export class TailscaleApiProxyChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleApiProxyChartProps) {
    super(scope, id, props);

    // Apply defaults
    const namespace = props.namespace || 'tailscale';
    const authKeySecretName = props.authKeySecretName || 'tailscale-auth-key';
    const tailscaleImage = props.tailscaleImage || 'tailscale/tailscale:latest';
    const kubectlImage = props.kubectlImage || 'bitnami/kubectl:latest';
    const proxyHostname = `${props.clusterName}-api`;

    // Create ExternalSecret for Tailscale auth key
    const authKeySecret = createEnvExternalSecret(this, 'tailscale-auth-key-external', {
      externalName: authKeySecretName,
      name: authKeySecretName,
      namespace: namespace,
      secretStoreRef: {
        name: 'azure-keyvault-store',
        kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
      },
      mappings: [
        { key: 'authKey', remoteRef: { key: 'TAILSCALE-AUTH-KEY' } }
      ]
    });
    authKeySecret.addJsonPatch(JsonPatch.add('/metadata/annotations', {
      'argocd.argoproj.io/sync-wave': '-80'
    }));

    // Create ServiceAccount for API access
    new k8s.KubeServiceAccount(this, 'api-proxy-sa', {
      metadata: {
        name: 'api-proxy',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
    });

    // Create ClusterRoleBinding for API access
    new k8s.KubeClusterRoleBinding(this, 'api-proxy-clusterrolebinding', {
      metadata: {
        name: 'tailscale-api-proxy',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'cluster-admin',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'api-proxy',
          namespace: namespace,
        },
      ],
    });

    // Create Deployment with Tailscale + kubectl-proxy sidecars
    new k8s.KubeDeployment(this, 'api-proxy-deployment', {
      metadata: {
        name: 'tailscale-api-proxy',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'tailscale-api-proxy',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'tailscale-api-proxy',
            },
          },
          spec: {
            serviceAccountName: 'api-proxy',
            containers: [
              {
                name: 'tailscale',
                image: tailscaleImage,
                env: [
                  {
                    name: 'TS_AUTHKEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: authKeySecretName,
                        key: 'authKey',
                      },
                    },
                  },
                  {
                    name: 'TS_HOSTNAME',
                    value: proxyHostname,
                  },
                  {
                    name: 'TS_STATE_DIR',
                    value: '/var/lib/tailscale',
                  },
                  {
                    name: 'TS_USERSPACE',
                    value: 'false',
                  },
                ],
                securityContext: {
                  capabilities: {
                    add: ['NET_ADMIN'],
                  },
                },
                volumeMounts: [
                  {
                    name: 'tailscale-state',
                    mountPath: '/var/lib/tailscale',
                  },
                  {
                    name: 'dev-net-tun',
                    mountPath: '/dev/net/tun',
                  },
                ],
              },
              {
                name: 'kubectl-proxy',
                image: kubectlImage,
                command: [
                  'kubectl',
                  'proxy',
                  '--port=8001',
                  '--address=0.0.0.0',
                  '--accept-hosts=.*',
                  '--reject-paths=^$', // Allow all paths
                ],
                ports: [
                  {
                    containerPort: 8001,
                    name: 'http',
                  },
                ],
                livenessProbe: {
                  httpGet: {
                    path: '/healthz',
                    port: k8s.IntOrString.fromNumber(8001),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/healthz',
                    port: k8s.IntOrString.fromNumber(8001),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                },
              },
            ],
            volumes: [
              {
                name: 'tailscale-state',
                emptyDir: {},
              },
              {
                name: 'dev-net-tun',
                hostPath: {
                  path: '/dev/net/tun',
                },
              },
            ],
          },
        },
      },
    });

    // Create Service for internal access (optional, for debugging)
    new k8s.KubeService(this, 'api-proxy-service', {
      metadata: {
        name: 'tailscale-api-proxy',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: {
          app: 'tailscale-api-proxy',
        },
        ports: [
          {
            port: 8001,
            targetPort: k8s.IntOrString.fromNumber(8001),
            protocol: 'TCP',
            name: 'http',
          },
        ],
      },
    });
  }
}
