/**
 * CaipeRagIngestorsChart - RAG Ingestors for CAIPE
 *
 * Deploys the RAG ingestor workers that process document ingestion jobs:
 * - Web URL ingestion (webloader)
 * - Document chunking and embedding generation
 * - Vector storage to Milvus
 * - Knowledge graph updates to Neo4j (GraphRAG)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  getCaipeRagLabels,
  getRagServerEnvVars,
} from '../../lib/caipe-helpers';

export interface CaipeRagIngestorsChartProps extends ChartProps {
  /**
   * Namespace for RAG Ingestors
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * RAG Ingestors image
   * @default 'ghcr.io/cnoe-io/caipe-rag-ingestors:latest'
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

export class CaipeRagIngestorsChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeRagIngestorsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/caipe-rag-ingestors:latest';
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const embeddingsSecretName = props.embeddingsSecretName || 'embeddings-secret';
    const neo4jSecretName = props.neo4jSecretName || 'neo4j-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.ragStack;

    const labels = getCaipeRagLabels('rag-ingestors');
    const selectorLabels = {
      'app.kubernetes.io/name': 'rag-ingestors',
      'app.kubernetes.io/instance': 'caipe-rag-ingestors',
    };

    const envVars = getRagServerEnvVars(namespace);

    // Deployment for RAG Ingestors (webloader)
    new k8s.KubeDeployment(this, 'rag-ingestors', {
      metadata: {
        name: 'rag-ingestors',
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
                name: 'rag-ingestors',
                image: image,
                command: ['python3', '-m', 'ingestors.webloader.ingestor'],
                workingDir: '/app/ingestors/src',
                env: [
                  // RAG Server backend URL (internal service)
                  {
                    name: 'RAG_SERVER_URL',
                    value: `http://rag-server.${namespace}.svc.cluster.local:${CAIPE_PORTS.ragServer}`,
                  },
                  // Embedding model configuration
                  { name: 'EMBEDDINGS_MODEL', value: 'text-embedding-3-large' },
                  // Database connections from helper
                  { name: 'MILVUS_URI', value: envVars.MILVUS_URI },
                  { name: 'NEO4J_ADDR', value: envVars.NEO4J_ADDR },
                  { name: 'NEO4J_ONTOLOGY_ADDR', value: envVars.NEO4J_ONTOLOGY_ADDR },
                  { name: 'NEO4J_USERNAME', value: envVars.NEO4J_USERNAME },
                  { name: 'REDIS_URL', value: envVars.REDIS_URL },
                  // GraphRAG settings
                  { name: 'ENABLE_GRAPH_RAG', value: 'true' },
                  // Python path for module imports
                  { name: 'PYTHONPATH', value: '/app/ingestors/src/ingestors/webloader:/app/ingestors/src' },
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: embeddingsSecretName,
                    },
                  },
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
                    memory: k8s.Quantity.fromString('512Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('2Gi'),
                    cpu: k8s.Quantity.fromString('1000m'),
                  },
                },
              },
            ],
          },
        },
      },
    });
  }
}
