/**
 * CaipeNeo4jChart - Neo4j graph database for CAIPE
 *
 * Deploys Neo4j community edition with memory limits configured for
 * resource-constrained environments (1GB heap, 512MB pagecache).
 *
 * Provides knowledge graph storage for GraphRAG queries.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_RESOURCE_LIMITS,
  getCaipeStorageLabels,
} from '../../lib/caipe-helpers';

export interface CaipeNeo4jChartProps extends ChartProps {
  /**
   * Namespace for Neo4j
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Storage size for Neo4j data
   * @default '10Gi'
   */
  storageSize?: string;

  /**
   * Storage class name
   * @default 'standard'
   */
  storageClassName?: string;

  /**
   * Secret name containing NEO4J_AUTH
   * @default 'neo4j-secret'
   */
  secretName?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '-50'
   */
  syncWave?: string;
}

export class CaipeNeo4jChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeNeo4jChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const storageSize = props.storageSize || '10Gi';
    const storageClassName = props.storageClassName || 'standard';
    const secretName = props.secretName || 'neo4j-secret';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.storage;

    const labels = getCaipeStorageLabels('neo4j');
    const selectorLabels = {
      'app.kubernetes.io/name': 'neo4j',
      'app.kubernetes.io/instance': 'caipe-neo4j',
    };

    // ConfigMap for Neo4j configuration
    new k8s.KubeConfigMap(this, 'neo4j-config', {
      metadata: {
        name: 'neo4j-config',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      data: {
        // Memory settings for 16GB shared environment
        'NEO4J_server_memory_heap_initial__size': CAIPE_RESOURCE_LIMITS.neo4j.heap,
        'NEO4J_server_memory_heap_max__size': CAIPE_RESOURCE_LIMITS.neo4j.heap,
        'NEO4J_server_memory_pagecache_size': CAIPE_RESOURCE_LIMITS.neo4j.pagecache,
        // Network settings
        'NEO4J_server_default__listen__address': '0.0.0.0',
        // Authentication
        'NEO4J_dbms_security_auth__enabled': 'true',
        // GraphRAG indexes: Create indexes on startup via extension configuration
        // These indexes support entity lookups for knowledge graph traversal
        'NEO4J_dbms_security_procedures_unrestricted': 'apoc.*',
        // Cypher initialization for entity indexes will be handled by NexiGraph on first connection
      },
    });

    // PersistentVolumeClaim for Neo4j data
    new k8s.KubePersistentVolumeClaim(this, 'neo4j-pvc', {
      metadata: {
        name: 'neo4j-data',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        storageClassName: storageClassName,
        resources: {
          requests: {
            storage: k8s.Quantity.fromString(storageSize),
          },
        },
      },
    });

    // StatefulSet for Neo4j
    new k8s.KubeStatefulSet(this, 'neo4j', {
      metadata: {
        name: 'neo4j',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        serviceName: 'neo4j',
        replicas: 1,
        selector: {
          matchLabels: selectorLabels,
        },
        template: {
          metadata: {
            labels: { ...labels, ...selectorLabels },
          },
          spec: {
            securityContext: {
              fsGroup: 7474,
              runAsUser: 7474,
              runAsGroup: 7474,
            },
            containers: [
              {
                name: 'neo4j',
                image: `neo4j:${CAIPE_RESOURCE_LIMITS.neo4j ? '5.18.0' : '5.18.0'}-community`,
                ports: [
                  { name: 'bolt', containerPort: CAIPE_PORTS.neo4jBolt },
                  { name: 'http', containerPort: CAIPE_PORTS.neo4jHttp },
                ],
                envFrom: [
                  {
                    configMapRef: {
                      name: 'neo4j-config',
                    },
                  },
                  {
                    secretRef: {
                      name: secretName,
                    },
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('1Gi'),
                    cpu: k8s.Quantity.fromString('250m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.neo4j.memory),
                    cpu: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.neo4j.cpu),
                  },
                },
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ],
                livenessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.neo4jHttp),
                  },
                  initialDelaySeconds: 60,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(CAIPE_PORTS.neo4jHttp),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                },
              },
            ],
            volumes: [
              {
                name: 'data',
                persistentVolumeClaim: {
                  claimName: 'neo4j-data',
                },
              },
            ],
          },
        },
      },
    });

    // Headless Service for StatefulSet
    new k8s.KubeService(this, 'neo4j-headless', {
      metadata: {
        name: 'neo4j',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        clusterIp: 'None',
        selector: selectorLabels,
        ports: [
          {
            name: 'bolt',
            port: CAIPE_PORTS.neo4jBolt,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.neo4jBolt),
            protocol: 'TCP',
          },
          {
            name: 'http',
            port: CAIPE_PORTS.neo4jHttp,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.neo4jHttp),
            protocol: 'TCP',
          },
        ],
      },
    });
  }
}
