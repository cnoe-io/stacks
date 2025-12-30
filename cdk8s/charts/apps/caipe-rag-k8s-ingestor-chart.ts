/**
 * CaipeRagK8sIngestorChart - Kubernetes Resource Ingestor for CAIPE GraphRAG
 *
 * Deploys the Kubernetes ingestor that:
 * - Fetches K8s resources (Deployments, Services, Ingresses, etc.)
 * - Converts them to graph entities
 * - Stores them in both Milvus (vector search) and Neo4j (graph traversal)
 * - Enables GraphRAG queries over cluster resources
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

export interface CaipeRagK8sIngestorChartProps extends ChartProps {
  /**
   * Namespace for K8s Ingestor
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Ingestor image
   * @default 'ghcr.io/cnoe-io/caipe-rag-ingestors:latest'
   */
  image?: string;

  /**
   * Cluster name for identifying resources
   * @default 'localdev'
   */
  clusterName?: string;

  /**
   * Kubernetes resource types to ingest
   * @default 'Deployment,Service,Ingress,Namespace,ConfigMap,Secret,StatefulSet,DaemonSet,CronJob,Job'
   */
  resourceList?: string;

  /**
   * Sync interval in seconds
   * @default 3600 (1 hour)
   */
  syncInterval?: number;

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

export class CaipeRagK8sIngestorChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeRagK8sIngestorChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const image = props.image || 'ghcr.io/cnoe-io/caipe-rag-ingestors:latest';
    const clusterName = props.clusterName || process.env.CLUSTER_NAME || 'localdev';
    const resourceList = props.resourceList || 'Deployment,Service,Ingress,Namespace,ConfigMap,StatefulSet,DaemonSet,CronJob,Job,Pod';
    const syncInterval = props.syncInterval || 3600;
    const llmSecretName = props.llmSecretName || 'llm-secret';
    const embeddingsSecretName = props.embeddingsSecretName || 'embeddings-secret';
    const neo4jSecretName = props.neo4jSecretName || 'neo4j-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.ragStack;

    const labels = getCaipeRagLabels('rag-k8s-ingestor');
    const selectorLabels = {
      'app.kubernetes.io/name': 'rag-k8s-ingestor',
      'app.kubernetes.io/instance': 'caipe-rag-k8s-ingestor',
    };

    const envVars = getRagServerEnvVars(namespace);

    // ServiceAccount for Kubernetes API access
    new k8s.KubeServiceAccount(this, 'rag-k8s-ingestor-sa', {
      metadata: {
        name: 'rag-k8s-ingestor',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
    });

    // ClusterRole for reading Kubernetes resources
    new k8s.KubeClusterRole(this, 'rag-k8s-ingestor-role', {
      metadata: {
        name: 'rag-k8s-ingestor',
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      rules: [
        {
          apiGroups: ['', 'apps', 'batch', 'networking.k8s.io', 'cert-manager.io', 'argoproj.io'],
          resources: [
            'namespaces',
            'pods',
            'services',
            'configmaps',
            'secrets',
            'deployments',
            'statefulsets',
            'daemonsets',
            'replicasets',
            'jobs',
            'cronjobs',
            'ingresses',
            'ingressclasses',
            'certificates',
            'clusterissuers',
            'issuers',
            'applications',
            'applicationsets',
          ],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['storage.k8s.io'],
          resources: ['storageclasses'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    // ClusterRoleBinding
    new k8s.KubeClusterRoleBinding(this, 'rag-k8s-ingestor-binding', {
      metadata: {
        name: 'rag-k8s-ingestor',
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'rag-k8s-ingestor',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'rag-k8s-ingestor',
          namespace: namespace,
        },
      ],
    });

    // Deployment for K8s Ingestor
    new k8s.KubeDeployment(this, 'rag-k8s-ingestor', {
      metadata: {
        name: 'rag-k8s-ingestor',
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
            serviceAccountName: 'rag-k8s-ingestor',
            containers: [
              {
                name: 'rag-k8s-ingestor',
                image: image,
                command: ['python3', '-m', 'ingestors.k8s.ingestor'],
                workingDir: '/app/ingestors/src',
                env: [
                  // Cluster identification
                  { name: 'CLUSTER_NAME', value: clusterName },
                  // In-cluster mode for ServiceAccount authentication
                  { name: 'IN_CLUSTER', value: 'true' },
                  // Resource types to ingest
                  { name: 'RESOURCE_LIST', value: resourceList },
                  // Sync interval
                  { name: 'SYNC_INTERVAL', value: String(syncInterval) },
                  // RAG Server backend URL
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
                  { name: 'PYTHONPATH', value: '/app/ingestors/src/ingestors/k8s:/app/ingestors/src' },
                  // Log level
                  { name: 'LOG_LEVEL', value: 'INFO' },
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
                    memory: k8s.Quantity.fromString('256Mi'),
                    cpu: k8s.Quantity.fromString('50m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('512Mi'),
                    cpu: k8s.Quantity.fromString('500m'),
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
