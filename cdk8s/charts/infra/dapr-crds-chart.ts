/**
 * DaprCrdsChart - Installs Dapr Custom Resource Definitions
 *
 * This chart deploys the Dapr CRDs that must exist before the Dapr runtime
 * or any Dapr components can be created. It should be synced with an earlier
 * sync wave than dapr-runtime.
 *
 * CRDs installed:
 * - components.dapr.io
 * - configurations.dapr.io
 * - subscriptions.dapr.io
 * - httpendpoints.dapr.io
 * - resiliencies.dapr.io
 *
 * Sync wave: -200 (before dapr-runtime at -100)
 */

import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

export interface DaprCrdsChartProps extends ChartProps {
  /**
   * Dapr version for CRDs (determines the CRD schema version)
   * @default 'v1.16.3'
   */
  daprVersion?: string;
}

export class DaprCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props: DaprCrdsChartProps = {}) {
    super(scope, id, props);

    const daprVersion = props.daprVersion || 'v1.16.3';
    const baseUrl = `https://raw.githubusercontent.com/dapr/dapr/${daprVersion}/charts/dapr/crds`;

    // Common labels for all CRDs
    const commonLabels = {
      'app.kubernetes.io/name': 'dapr',
      'app.kubernetes.io/part-of': 'dapr',
      'app.kubernetes.io/managed-by': 'cdk8s',
      'app.kubernetes.io/version': daprVersion.replace('v', ''),
    };

    // Component CRD - defines Dapr building blocks (pubsub, state, bindings, etc.)
    new ApiObject(this, 'components-crd', {
      apiVersion: 'apiextensions.k8s.io/v1',
      kind: 'CustomResourceDefinition',
      metadata: {
        name: 'components.dapr.io',
        labels: commonLabels,
        annotations: {
          'controller-gen.kubebuilder.io/version': 'v0.15.0',
        },
      },
      spec: {
        group: 'dapr.io',
        names: {
          kind: 'Component',
          listKind: 'ComponentList',
          plural: 'components',
          singular: 'component',
        },
        scope: 'Namespaced',
        versions: [
          {
            name: 'v1alpha1',
            served: true,
            storage: true,
            schema: {
              openAPIV3Schema: {
                type: 'object',
                properties: {
                  apiVersion: { type: 'string' },
                  kind: { type: 'string' },
                  metadata: { type: 'object' },
                  spec: {
                    type: 'object',
                    properties: {
                      type: { type: 'string' },
                      version: { type: 'string' },
                      metadata: {
                        type: 'array',
                        items: {
                          type: 'object',
                          properties: {
                            name: { type: 'string' },
                            value: { type: 'string' },
                            secretKeyRef: {
                              type: 'object',
                              properties: {
                                name: { type: 'string' },
                                key: { type: 'string' },
                              },
                            },
                          },
                        },
                      },
                      scopes: {
                        type: 'array',
                        items: { type: 'string' },
                      },
                      ignoreErrors: { type: 'boolean' },
                      initTimeout: { type: 'string' },
                    },
                  },
                  auth: {
                    type: 'object',
                    properties: {
                      secretStore: { type: 'string' },
                    },
                  },
                  scopes: {
                    type: 'array',
                    items: { type: 'string' },
                  },
                },
              },
            },
            additionalPrinterColumns: [
              {
                name: 'Type',
                type: 'string',
                jsonPath: '.spec.type',
              },
              {
                name: 'Version',
                type: 'string',
                jsonPath: '.spec.version',
              },
              {
                name: 'Age',
                type: 'date',
                jsonPath: '.metadata.creationTimestamp',
              },
            ],
          },
        ],
      },
    });

    // Configuration CRD - defines Dapr runtime configuration
    new ApiObject(this, 'configurations-crd', {
      apiVersion: 'apiextensions.k8s.io/v1',
      kind: 'CustomResourceDefinition',
      metadata: {
        name: 'configurations.dapr.io',
        labels: commonLabels,
        annotations: {
          'controller-gen.kubebuilder.io/version': 'v0.15.0',
        },
      },
      spec: {
        group: 'dapr.io',
        names: {
          kind: 'Configuration',
          listKind: 'ConfigurationList',
          plural: 'configurations',
          singular: 'configuration',
        },
        scope: 'Namespaced',
        versions: [
          {
            name: 'v1alpha1',
            served: true,
            storage: true,
            schema: {
              openAPIV3Schema: {
                type: 'object',
                properties: {
                  apiVersion: { type: 'string' },
                  kind: { type: 'string' },
                  metadata: { type: 'object' },
                  spec: {
                    type: 'object',
                    'x-kubernetes-preserve-unknown-fields': true,
                  },
                },
              },
            },
          },
        ],
      },
    });

    // Subscription CRD - defines pub/sub topic subscriptions
    new ApiObject(this, 'subscriptions-crd', {
      apiVersion: 'apiextensions.k8s.io/v1',
      kind: 'CustomResourceDefinition',
      metadata: {
        name: 'subscriptions.dapr.io',
        labels: commonLabels,
        annotations: {
          'controller-gen.kubebuilder.io/version': 'v0.15.0',
        },
      },
      spec: {
        group: 'dapr.io',
        names: {
          kind: 'Subscription',
          listKind: 'SubscriptionList',
          plural: 'subscriptions',
          singular: 'subscription',
        },
        scope: 'Namespaced',
        versions: [
          {
            name: 'v1alpha1',
            served: true,
            storage: false,
            schema: {
              openAPIV3Schema: {
                type: 'object',
                properties: {
                  apiVersion: { type: 'string' },
                  kind: { type: 'string' },
                  metadata: { type: 'object' },
                  spec: {
                    type: 'object',
                    'x-kubernetes-preserve-unknown-fields': true,
                  },
                  scopes: {
                    type: 'array',
                    items: { type: 'string' },
                  },
                },
              },
            },
          },
          {
            name: 'v2alpha1',
            served: true,
            storage: true,
            schema: {
              openAPIV3Schema: {
                type: 'object',
                properties: {
                  apiVersion: { type: 'string' },
                  kind: { type: 'string' },
                  metadata: { type: 'object' },
                  spec: {
                    type: 'object',
                    'x-kubernetes-preserve-unknown-fields': true,
                  },
                  scopes: {
                    type: 'array',
                    items: { type: 'string' },
                  },
                },
              },
            },
          },
        ],
        conversion: {
          strategy: 'Webhook',
          webhook: {
            conversionReviewVersions: ['v1'],
            clientConfig: {
              service: {
                namespace: 'dapr-system',
                name: 'dapr-operator',
                path: '/convert',
              },
            },
          },
        },
      },
    });

    // HTTPEndpoint CRD - defines HTTP endpoints for service invocation
    new ApiObject(this, 'httpendpoints-crd', {
      apiVersion: 'apiextensions.k8s.io/v1',
      kind: 'CustomResourceDefinition',
      metadata: {
        name: 'httpendpoints.dapr.io',
        labels: commonLabels,
        annotations: {
          'controller-gen.kubebuilder.io/version': 'v0.15.0',
        },
      },
      spec: {
        group: 'dapr.io',
        names: {
          kind: 'HTTPEndpoint',
          listKind: 'HTTPEndpointList',
          plural: 'httpendpoints',
          singular: 'httpendpoint',
        },
        scope: 'Namespaced',
        versions: [
          {
            name: 'v1alpha1',
            served: true,
            storage: true,
            schema: {
              openAPIV3Schema: {
                type: 'object',
                properties: {
                  apiVersion: { type: 'string' },
                  kind: { type: 'string' },
                  metadata: { type: 'object' },
                  spec: {
                    type: 'object',
                    'x-kubernetes-preserve-unknown-fields': true,
                  },
                  auth: {
                    type: 'object',
                    properties: {
                      secretStore: { type: 'string' },
                    },
                  },
                  scopes: {
                    type: 'array',
                    items: { type: 'string' },
                  },
                },
              },
            },
          },
        ],
      },
    });

    // Resiliency CRD - defines retry, timeout, circuit breaker policies
    new ApiObject(this, 'resiliencies-crd', {
      apiVersion: 'apiextensions.k8s.io/v1',
      kind: 'CustomResourceDefinition',
      metadata: {
        name: 'resiliencies.dapr.io',
        labels: commonLabels,
        annotations: {
          'controller-gen.kubebuilder.io/version': 'v0.15.0',
        },
      },
      spec: {
        group: 'dapr.io',
        names: {
          kind: 'Resiliency',
          listKind: 'ResiliencyList',
          plural: 'resiliencies',
          singular: 'resiliency',
        },
        scope: 'Namespaced',
        versions: [
          {
            name: 'v1alpha1',
            served: true,
            storage: true,
            schema: {
              openAPIV3Schema: {
                type: 'object',
                properties: {
                  apiVersion: { type: 'string' },
                  kind: { type: 'string' },
                  metadata: { type: 'object' },
                  spec: {
                    type: 'object',
                    'x-kubernetes-preserve-unknown-fields': true,
                  },
                  scopes: {
                    type: 'array',
                    items: { type: 'string' },
                  },
                },
              },
            },
          },
        ],
      },
    });
  }
}
