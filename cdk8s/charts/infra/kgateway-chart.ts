/**
 * KgatewayChart - Deploys kgateway with agentgateway enabled
 *
 * This chart deploys kgateway v2.2.0 with:
 * - agentGateway.enabled=true (MCP server gateway functionality)
 * - gateway.aiExtension.enabled=true (AI-native gateway features)
 *
 * Provides:
 * - MCP protocol traffic management
 * - A2A (Agent-to-Agent) protocol support
 * - LLM routing and failover
 * - Rate limiting and security policies
 * - OpenTelemetry integration (via GatewayParameters CRD)
 *
 * Must be deployed after kgateway CRDs
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeNamespace, KubeIngress, KubeService, IntOrString } from '../../imports/k8s';
import {
  Gateway,
  GatewayClass,
  GatewaySpecListenersAllowedRoutesNamespacesFrom
} from '../../imports/gateway.networking.k8s.io';

export interface KgatewayChartProps extends ChartProps {
  /**
   * kgateway Helm chart version
   * @default 'v2.1.1'
   */
  version?: string;

  /**
   * Namespace for kgateway components
   * @default 'kgateway-system'
   */
  namespace?: string;

  /**
   * Enable agentgateway (MCP server gateway)
   * @default true
   */
  enableAgentGateway?: boolean;

  /**
   * Enable AI extension features
   * @default true
   */
  enableAiExtension?: boolean;

  /**
   * Control plane replicas
   * @default 1
   */
  replicas?: number;
}

export class KgatewayChart extends Chart {
  constructor(scope: Construct, id: string, props: KgatewayChartProps = {}) {
    super(scope, id, props);

    const version = props.version || 'v2.1.1';
    const namespace = props.namespace || 'kgateway-system';
    const enableAgentGateway = props.enableAgentGateway !== false; // Default true
    const enableAiExtension = props.enableAiExtension !== false; // Default true
    const replicas = props.replicas || 1;

    // Create namespace
    new KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespace,
        labels: {
          'app.kubernetes.io/name': 'kgateway',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // Deploy kgateway with agentgateway enabled
    new Helm(this, 'kgateway', {
      chart: 'oci://cr.kgateway.dev/kgateway-dev/charts/kgateway',
      version: version,
      namespace: namespace,
      releaseName: 'kgateway',
      values: {
        // Enable agentgateway for MCP server gateway functionality
        // Note: Uses lowercase 'agentgateway' per Helm chart schema
        agentgateway: {
          enabled: enableAgentGateway,
        },

        // Enable Inference Extension (requires agentgateway.enabled=true)
        inferenceExtension: {
          enabled: enableAiExtension,
        },

        // Control plane configuration
        gloo: {
          deployment: {
            replicas: replicas,
            resources: {
              requests: {
                cpu: '100m',
                memory: '256Mi',
              },
              limits: {
                cpu: '1000m',
                memory: '1Gi',
              },
            },
          },
        },

        // Gateway proxy configuration
        gatewayProxies: {
          gatewayProxy: {
            service: {
              type: 'ClusterIP',
            },
            podTemplate: {
              resources: {
                requests: {
                  cpu: '100m',
                  memory: '256Mi',
                },
                limits: {
                  cpu: '1000m',
                  memory: '1Gi',
                },
              },
            },
          },
        },

        // Global settings
        global: {
          image: {
            pullPolicy: 'IfNotPresent',
          },
        },
      },
    });

    // Create agentgateway GatewayClass if enabled
    if (enableAgentGateway) {
      new GatewayClass(this, 'agentgateway-class', {
        metadata: {
          name: 'agentgateway',
        },
        spec: {
          controllerName: 'kgateway.dev/agentgateway',
        },
      });

      // Create agentgateway Gateway proxy
      new Gateway(this, 'agentgateway-gateway', {
        metadata: {
          name: 'agentgateway',
          namespace: namespace,
          labels: {
            app: 'agentgateway',
          },
        },
        spec: {
          gatewayClassName: 'agentgateway',
          listeners: [
            {
              protocol: 'HTTP',
              port: 8080,
              name: 'http',
              allowedRoutes: {
                namespaces: {
                  from: GatewaySpecListenersAllowedRoutesNamespacesFrom.ALL,
                },
              },
            },
          ],
        },
      });

      // Create Ingress for agentgateway access
      const baseHost = process.env.INGRESS_HOST || 'cnoe.localtest.me';
      const agentgatewayHost = `agentgateway.${baseHost}`;

      new KubeIngress(this, 'agentgateway-ingress', {
        metadata: {
          name: 'agentgateway',
          namespace: namespace,
          annotations: {
            'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          },
        },
        spec: {
          ingressClassName: 'nginx',
          rules: [
            {
              host: agentgatewayHost,
              http: {
                paths: [
                  {
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
                  },
                ],
              },
            },
          ],
        },
      });

      // Create Service for agentgateway admin UI (port 15000)
      const agentgatewayAdminHost = `agentgateway-admin.${baseHost}`;

      new KubeService(this, 'agentgateway-admin-service', {
        metadata: {
          name: 'agentgateway-admin',
          namespace: namespace,
          labels: {
            app: 'agentgateway-admin',
          },
        },
        spec: {
          type: 'ClusterIP',
          selector: {
            'gateway.networking.k8s.io/gateway-name': 'agentgateway',
          },
          ports: [
            {
              name: 'admin',
              port: 15000,
              targetPort: IntOrString.fromNumber(15000),
              protocol: 'TCP',
            },
          ],
        },
      });

      // Create Ingress for agentgateway admin UI
      new KubeIngress(this, 'agentgateway-admin-ingress', {
        metadata: {
          name: 'agentgateway-admin',
          namespace: namespace,
          annotations: {
            'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          },
        },
        spec: {
          ingressClassName: 'nginx',
          rules: [
            {
              host: agentgatewayAdminHost,
              http: {
                paths: [
                  {
                    path: '/',
                    pathType: 'Prefix',
                    backend: {
                      service: {
                        name: 'agentgateway-admin',
                        port: {
                          number: 15000,
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
    }
  }
}
