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
   * Sync wave for ArgoCD ordering
   * @default '0'
   */
  syncWave?: string;
}

export class CaipeRagServerChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeRagServerChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/caipe-rag-server:latest';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const embeddingsSecretName = props.embeddingsSecretName || 'embeddings-secret';
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
                  // Database connections from helper
                  { name: 'MILVUS_HOST', value: envVars.MILVUS_HOST },
                  { name: 'MILVUS_PORT', value: envVars.MILVUS_PORT },
                  { name: 'NEO4J_URI', value: envVars.NEO4J_URI },
                  { name: 'REDIS_URL', value: envVars.REDIS_URL },
                  // Embedding model configuration
                  { name: 'EMBEDDING_MODEL', value: 'text-embedding-3-small' },
                  { name: 'EMBEDDING_DIMENSION', value: '1536' },
                  // NexiGraph (agent-ontology) connection for GraphRAG
                  { name: 'NEXIGRAPH_URL', value: `http://nexigraph.${namespace}.svc.cluster.local:${CAIPE_PORTS.agentOntology}` },
                  // GraphRAG hybrid retrieval settings
                  { name: 'ENABLE_GRAPHRAG', value: 'true' },
                  { name: 'GRAPH_RETRIEVAL_DEPTH', value: '2' },
                  { name: 'HYBRID_RETRIEVAL_WEIGHT', value: '0.5' },
                  // Document ingestion settings
                  { name: 'MAX_DOCUMENT_SIZE_MB', value: '10' },
                  { name: 'ENABLE_PDF_PARSING', value: 'true' },
                  { name: 'ENABLE_WEB_FETCHING', value: 'true' },
                  { name: 'CHUNK_SIZE', value: '512' },
                  { name: 'CHUNK_OVERLAP', value: '50' },
                  // Observability - Prometheus metrics
                  { name: 'METRICS_ENABLED', value: 'true' },
                  // Observability - OpenTelemetry
                  { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: 'http://otel-collector.observability.svc.cluster.local:4317' },
                  { name: 'OTEL_SERVICE_NAME', value: 'rag-server' },
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
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragServer),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/health',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.ragServer),
                  },
                  initialDelaySeconds: 10,
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
