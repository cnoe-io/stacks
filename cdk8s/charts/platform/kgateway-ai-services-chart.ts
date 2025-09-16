import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * KGatewayAIServicesChart creates Backend and HTTPRoute resources for AI services
 * This enables routing to OpenAI, Anthropic, and other AI providers through AgentGateway
 */
export class KGatewayAIServicesChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const kgatewayNamespace = 'kgateway-system';
    const aiServicesNamespace = 'ai-services';

    // Create namespace for AI services
    new k8s.KubeNamespace(this, 'ai-services-namespace', {
      metadata: {
        name: aiServicesNamespace,
        labels: {
          'app.kubernetes.io/name': 'ai-services',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '10',
        },
      },
    });

    // Create OpenAI Backend resource
    new ApiObject(this, 'openai-backend', {
      apiVersion: 'gateway.kgateway.dev/v1alpha1',
      kind: 'Backend',
      metadata: {
        name: 'openai',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'openai',
          'app.kubernetes.io/component': 'backend',
          'app.kubernetes.io/part-of': 'kgateway',
          'ai.kgateway.dev/provider': 'openai',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          'ai.kgateway.dev/models': 'gpt-4,gpt-4-turbo,gpt-3.5-turbo,text-embedding-ada-002',
        },
      },
      spec: {
        type: 'AI',
        ai: {
          llm: {
            provider: {
              openai: {
                model: 'gpt-4',
                authToken: {
                  kind: 'SecretRef',
                  secretRef: {
                    name: 'openai-credentials',
                  },
                },
              },
            },
          },
        },
      },
    });

    // Create Anthropic Backend resource
    new ApiObject(this, 'anthropic-backend', {
      apiVersion: 'gateway.kgateway.dev/v1alpha1',
      kind: 'Backend',
      metadata: {
        name: 'anthropic',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'anthropic',
          'app.kubernetes.io/component': 'backend',
          'app.kubernetes.io/part-of': 'kgateway',
          'ai.kgateway.dev/provider': 'anthropic',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          'ai.kgateway.dev/models': 'claude-3-opus,claude-3-sonnet,claude-3-haiku',
        },
      },
      spec: {
        type: 'AI',
        ai: {
          llm: {
            provider: {
              anthropic: {
                model: 'claude-3-opus-20240229',
                authToken: {
                  kind: 'SecretRef',
                  secretRef: {
                    name: 'anthropic-credentials',
                  },
                },
              },
            },
          },
        },
      },
    });

    // Create unified AI HTTPRoute
    new ApiObject(this, 'ai-services-route', {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: 'ai-services',
        namespace: kgatewayNamespace,
        labels: {
          'app.kubernetes.io/name': 'ai-services',
          'app.kubernetes.io/component': 'route',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '30',
          'ai.kgateway.dev/description': 'Unified AI services routing',
        },
      },
      spec: {
        parentRefs: [
          {
            name: 'agentgateway',
            namespace: kgatewayNamespace,
          },
        ],
        hostnames: ['ai.cnoe.localtest.me'],
        rules: [
          // OpenAI route
          {
            matches: [
              {
                path: {
                  type: 'PathPrefix',
                  value: '/openai',
                },
              },
            ],
            filters: [
              {
                type: 'URLRewrite',
                urlRewrite: {
                  path: {
                    type: 'ReplacePrefixMatch',
                    replacePrefixMatch: '/v1',
                  },
                },
              },
              {
                type: 'RequestHeaderModifier',
                requestHeaderModifier: {
                  set: [
                    {
                      name: 'X-AI-Provider',
                      value: 'openai',
                    },
                  ],
                },
              },
            ],
            backendRefs: [
              {
                group: 'gateway.kgateway.dev',
                kind: 'Backend',
                name: 'openai',
              },
            ],
          },
          // Anthropic route
          {
            matches: [
              {
                path: {
                  type: 'PathPrefix',
                  value: '/anthropic',
                },
              },
            ],
            filters: [
              {
                type: 'URLRewrite',
                urlRewrite: {
                  path: {
                    type: 'ReplacePrefixMatch',
                    replacePrefixMatch: '/v1',
                  },
                },
              },
              {
                type: 'RequestHeaderModifier',
                requestHeaderModifier: {
                  set: [
                    {
                      name: 'X-AI-Provider',
                      value: 'anthropic',
                    },
                  ],
                },
              },
            ],
            backendRefs: [
              {
                group: 'gateway.kgateway.dev',
                kind: 'Backend',
                name: 'anthropic',
              },
            ],
          },
          // Unified AI endpoint (provider selection via header)
          {
            matches: [
              {
                path: {
                  type: 'PathPrefix',
                  value: '/ai',
                },
                headers: [
                  {
                    name: 'X-AI-Provider',
                    value: 'openai',
                  },
                ],
              },
            ],
            backendRefs: [
              {
                group: 'gateway.kgateway.dev',
                kind: 'Backend',
                name: 'openai',
              },
            ],
          },
          {
            matches: [
              {
                path: {
                  type: 'PathPrefix',
                  value: '/ai',
                },
                headers: [
                  {
                    name: 'X-AI-Provider',
                    value: 'anthropic',
                  },
                ],
              },
            ],
            backendRefs: [
              {
                group: 'gateway.kgateway.dev',
                kind: 'Backend',
                name: 'anthropic',
              },
            ],
          },
        ],
      },
    });

    // Create Secret placeholders for API keys (will be populated from 1Password)
    new k8s.KubeSecret(this, 'openai-credentials', {
      metadata: {
        name: 'openai-credentials',
        namespace: aiServicesNamespace,
        labels: {
          'app.kubernetes.io/name': 'openai-credentials',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '15',
          'ai.kgateway.dev/provider': 'openai',
          'external-secrets.io/managed': 'true', // Indicates this should be managed by External Secrets
        },
      },
      stringData: {
        'api-key': 'placeholder-will-be-replaced-by-external-secrets',
      },
    });

    new k8s.KubeSecret(this, 'anthropic-credentials', {
      metadata: {
        name: 'anthropic-credentials',
        namespace: aiServicesNamespace,
        labels: {
          'app.kubernetes.io/name': 'anthropic-credentials',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '15',
          'ai.kgateway.dev/provider': 'anthropic',
          'external-secrets.io/managed': 'true', // Indicates this should be managed by External Secrets
        },
      },
      stringData: {
        'api-key': 'placeholder-will-be-replaced-by-external-secrets',
      },
    });

    // Create ExternalSecret resources to fetch from 1Password
    new ApiObject(this, 'openai-external-secret', {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: {
        name: 'openai-credentials',
        namespace: aiServicesNamespace,
        labels: {
          'app.kubernetes.io/name': 'openai-credentials',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '16',
        },
      },
      spec: {
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: 'ClusterSecretStore',
        },
        target: {
          name: 'openai-credentials',
          creationPolicy: 'Owner',
        },
        data: [
          {
            secretKey: 'api-key',
            remoteRef: {
              key: 'OPENAI-API-KEY',
            },
          },
        ],
      },
    });

    new ApiObject(this, 'anthropic-external-secret', {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: {
        name: 'anthropic-credentials',
        namespace: aiServicesNamespace,
        labels: {
          'app.kubernetes.io/name': 'anthropic-credentials',
          'app.kubernetes.io/part-of': 'kgateway',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '16',
        },
      },
      spec: {
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: 'ClusterSecretStore',
        },
        target: {
          name: 'anthropic-credentials',
          creationPolicy: 'Owner',
        },
        data: [
          {
            secretKey: 'api-key',
            remoteRef: {
              key: 'ANTHROPIC-API-KEY',
            },
          },
        ],
      },
    });
  }
}