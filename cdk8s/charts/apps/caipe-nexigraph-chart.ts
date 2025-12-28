/**
 * CaipeNexigraphChart - NexiGraph (Agent Ontology) for CAIPE GraphRAG
 *
 * Deploys the NexiGraph service that provides:
 * - Entity extraction from documents
 * - Knowledge graph construction
 * - Graph-based retrieval for GraphRAG queries
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_RESOURCE_LIMITS,
  getCaipeRagLabels,
} from '../../lib/caipe-helpers';

export interface CaipeNexigraphChartProps extends ChartProps {
  /**
   * Namespace for NexiGraph
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * NexiGraph (agent-ontology) image
   * @default 'ghcr.io/cnoe-io/agent-ontology:0.2.4'
   */
  image?: string;

  /**
   * Secret name for LLM credentials
   * @default 'llm-secret'
   */
  llmSecretName?: string;

  /**
   * Secret name for Neo4j credentials
   * @default 'neo4j-secret'
   */
  neo4jSecretName?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '0'
   */
  syncWave?: string;
}

export class CaipeNexigraphChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeNexigraphChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/nexigraph-clients:latest';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const neo4jSecretName = props.neo4jSecretName || 'neo4j-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.ragStack;

    const labels = getCaipeRagLabels('nexigraph');
    const selectorLabels = {
      'app.kubernetes.io/name': 'nexigraph',
      'app.kubernetes.io/instance': 'caipe-nexigraph',
    };

    // Deployment for NexiGraph
    new k8s.KubeDeployment(this, 'nexigraph', {
      metadata: {
        name: 'nexigraph',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: selectorLabels,
        },
        template: {
          metadata: {
            labels: { ...labels, ...selectorLabels },
          },
          spec: {
            containers: [
              {
                name: 'nexigraph',
                image: image,
                ports: [
                  {
                    name: 'http',
                    containerPort: CAIPE_PORTS.agentOntology,
                  },
                ],
                env: [
                  // API key for LLM access (maps from secret)
                  {
                    name: 'API_KEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: llmSecretName,
                        key: 'AZURE_OPENAI_API_KEY',
                      },
                    },
                  },
                  // Neo4j connection
                  {
                    name: 'NEO4J_URI',
                    value: `bolt://neo4j.${namespace}.svc.cluster.local:${CAIPE_PORTS.neo4jBolt}`,
                  },
                  // Entity extraction settings
                  { name: 'EXTRACTION_MODEL', value: 'gpt-4o' },
                  { name: 'MAX_ENTITIES_PER_DOCUMENT', value: '100' },
                  { name: 'MAX_RELATIONSHIPS_PER_ENTITY', value: '10' },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: llmSecretName,
                    },
                  },
                  {
                    secretRef: {
                      name: neo4jSecretName,
                    },
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('1Gi'),
                    cpu: k8s.Quantity.fromString('250m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.agentOntology.memory),
                    cpu: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.agentOntology.cpu),
                  },
                },
                livenessProbe: {
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.agentOntology),
                  },
                  initialDelaySeconds: 60,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.agentOntology),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                },
              },
            ],
          },
        },
      },
    });

    // Service for NexiGraph
    new k8s.KubeService(this, 'nexigraph-svc', {
      metadata: {
        name: 'nexigraph',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: selectorLabels,
        ports: [
          {
            name: 'http',
            port: CAIPE_PORTS.agentOntology,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.agentOntology),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });
  }
}
