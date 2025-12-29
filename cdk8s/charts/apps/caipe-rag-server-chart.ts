/**
 * CaipeRagServerChart - RAG Server for CAIPE
 *
 * Deploys the RAG (Retrieval-Augmented Generation) server that provides:
 * - Document ingestion with chunking and embedding
 * - Vector similarity search via Milvus
 * - Knowledge graph queries via Neo4j
 * - Hybrid retrieval (GraphRAG)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_RESOURCE_LIMITS,
  CAIPE_OBSERVABILITY,
  getCaipeRagLabels,
  getRagServerEnvVars,
} from '../../lib/caipe-helpers';

export interface CaipeRagServerChartProps extends ChartProps {
  /**
   * Namespace for RAG Server
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * RAG Server image
   * @default 'ghcr.io/cnoe-io/rag-server:0.2.4'
   */
  image?: string;

  /**
   * Secret name for LLM credentials
   * @default 'llm-secret'
   */
  llmSecretName?: string;

  /**
   * Secret name for embeddings credentials
   * @default 'embeddings-secret'
   */
  embeddingsSecretName?: string;

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

export class CaipeRagServerChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeRagServerChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    // Use official CAIPE rag-server image with stable tag
    const image = props.image || 'ghcr.io/cnoe-io/caipe-rag-server:stable';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const embeddingsSecretName = props.embeddingsSecretName || 'embeddings-secret';
    const neo4jSecretName = props.neo4jSecretName || 'neo4j-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.ragStack;

    const labels = getCaipeRagLabels('rag-server');
    const selectorLabels = {
      'app.kubernetes.io/name': 'rag-server',
      'app.kubernetes.io/instance': 'caipe-rag-server',
    };

    const envVars = getRagServerEnvVars(namespace);

    // Deployment for RAG Server
    new k8s.KubeDeployment(this, 'rag-server', {
      metadata: {
        name: 'rag-server',
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
                name: 'rag-server',
                image: image,
                ports: [
                  {
                    name: 'http',
                    containerPort: CAIPE_PORTS.ragServer,
                  },
                ],
                env: [
                  // Database connections from helper (official CAIPE env var names)
                  { name: 'MILVUS_URI', value: envVars.MILVUS_URI },
                  { name: 'NEO4J_ADDR', value: envVars.NEO4J_ADDR },
                  { name: 'NEO4J_ONTOLOGY_ADDR', value: envVars.NEO4J_ONTOLOGY_ADDR },
                  { name: 'NEO4J_USERNAME', value: envVars.NEO4J_USERNAME },
                  { name: 'REDIS_URL', value: envVars.REDIS_URL },
                  // Agent ontology connection for GraphRAG
                  { name: 'ONTOLOGY_AGENT_RESTAPI_ADDR', value: envVars.ONTOLOGY_AGENT_RESTAPI_ADDR },
                  // Embedding model configuration
                  { name: 'EMBEDDINGS_MODEL', value: 'text-embedding-3-large' },
                  // GraphRAG settings
                  { name: 'ENABLE_GRAPH_RAG', value: 'true' },
                  // Cleanup interval in seconds (24 hours)
                  { name: 'CLEANUP_INTERVAL', value: '86400' },
                  // Log level
                  { name: 'LOG_LEVEL', value: 'DEBUG' },
                  // Observability - cnoe-agent-utils tracing control
                  { name: 'ENABLE_TRACING', value: CAIPE_OBSERVABILITY.tracing.enabled },
                  // Observability - OpenTelemetry for distributed tracing (Tempo)
                  { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: CAIPE_OBSERVABILITY.otel.grpcEndpoint },
                  { name: 'OTEL_SERVICE_NAME', value: 'caipe-rag-server' },
                  // Observability - Langfuse for LLM-specific tracing
                  { name: 'LANGFUSE_ENABLED', value: CAIPE_OBSERVABILITY.langfuse.enabled },
                  { name: 'LANGFUSE_HOST', value: CAIPE_OBSERVABILITY.langfuse.host },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: llmSecretName,
                    },
                  },
                  {
                    secretRef: {
                      name: embeddingsSecretName,
                    },
                  },
                  {
                    secretRef: {
                      name: neo4jSecretName,
                    },
                  },
                  {
                    // Langfuse API credentials for tracing
                    secretRef: {
                      name: 'caipe-langfuse-credentials',
                    },
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('256Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.ragServer.memory),
                    cpu: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.ragServer.cpu),
                  },
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragServer),
                  },
                  initialDelaySeconds: 60,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                  failureThreshold: 5,
                },
                readinessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragServer),
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

    // Service for RAG Server
    new k8s.KubeService(this, 'rag-server-svc', {
      metadata: {
        name: 'rag-server',
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
            port: CAIPE_PORTS.ragServer,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragServer),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });
  }
}
