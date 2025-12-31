# CAIPE (AI Platform Engineering) Applications
# Multi-Agent System with RAG stack, GraphRAG, and multi-agent coordination
# Mirrors: cdk8s/charts/apps/caipe-*.ts
# KIND only for initial development
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost name;
  namespace = "ai-platform-engineering";
  isKind = environmentType == "kind";
  clusterSuffix = if name != "" then "-${name}" else "";
  clusterId = if name != "" then name else "localdev";
in
{
  # =========================================================================
  # Phase 2: Foundational Infrastructure
  # =========================================================================

  # CAIPE Namespace
  applications.caipe-namespace = lib.mkIf isKind {
    inherit namespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-110";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
      };
    };

    resources = {
      namespaces.${namespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "namespace";
          "app.kubernetes.io/part-of" = "ai-platform-engineering";
        };
      };
    };
  };

  # CAIPE Secrets
  applications.caipe-secrets = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-80";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
      retry = {
        limit = 10;
        backoff = {
          duration = "5s";
          factor = 2;
          maxDuration = "3m";
        };
      };
    };

    yamls = [
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: llm-secret
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: llm-secret
            creationPolicy: Owner
          data:
            - secretKey: OPENAI_API_KEY
              remoteRef:
                key: OPENAI-API-KEY
            - secretKey: ANTHROPIC_API_KEY
              remoteRef:
                key: ANTHROPIC-API-KEY
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: embeddings-secret
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: embeddings-secret
            creationPolicy: Owner
          data:
            - secretKey: OPENAI_API_KEY
              remoteRef:
                key: OPENAI-API-KEY
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: neo4j-secret
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: neo4j-secret
            creationPolicy: Owner
          data:
            - secretKey: NEO4J_AUTH
              remoteRef:
                key: NEO4J-AUTH
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: agent-argocd-secret
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: agent-argocd-secret
            creationPolicy: Owner
          data:
            - secretKey: ARGOCD_AUTH_TOKEN
              remoteRef:
                key: CAIPE-ARGOCD-TOKEN-${lib.toUpper clusterId}
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: agent-github-secret
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: agent-github-secret
            creationPolicy: Owner
          data:
            - secretKey: GITHUB_TOKEN
              remoteRef:
                key: GITHUB-PAT
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: agent-backstage-secret
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: agent-backstage-secret
            creationPolicy: Owner
          data:
            - secretKey: BACKSTAGE_API_TOKEN
              remoteRef:
                key: CAIPE-BACKSTAGE-API-TOKEN-${lib.toUpper clusterId}
      ''
    ];
  };

  # CAIPE Token Sync (ArgoCD token synchronization)
  applications.caipe-token-sync = lib.mkIf isKind {
    namespace = "argocd";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    yamls = [
      ''
        apiVersion: batch/v1
        kind: CronJob
        metadata:
          name: caipe-argocd-token-sync
          namespace: argocd
        spec:
          schedule: "0 */6 * * *"
          jobTemplate:
            spec:
              template:
                spec:
                  serviceAccountName: argocd-server
                  containers:
                    - name: token-sync
                      image: quay.io/argoproj/argocd:v2.14.11
                      env:
                        - name: HOME
                          value: /tmp
                        - name: ARGOCD_SERVER
                          value: argocd-server.argocd.svc.cluster.local
                      command:
                        - /bin/sh
                        - -c
                        - |
                          argocd login $ARGOCD_SERVER --core
                          TOKEN=$(argocd account generate-token --account developer)
                          echo "Token generated successfully"
                  restartPolicy: OnFailure
      ''
    ];
  };

  # =========================================================================
  # Storage Tier
  # =========================================================================

  # CAIPE Milvus (Vector Database)
  applications.caipe-milvus = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      statefulSets.milvus = {
        metadata = {
          inherit namespace;
          labels = {
            app = "milvus";
            tier = "storage";
          };
        };
        spec = {
          replicas = 1;
          serviceName = "milvus";
          selector.matchLabels.app = "milvus";

          template = {
            metadata.labels.app = "milvus";

            spec.containers = [{
              name = "milvus";
              image = "milvusdb/milvus:v2.3.4";
              ports = [
                { containerPort = 19530; name = "grpc"; }
                { containerPort = 9091; name = "metrics"; }
              ];
              command = ["milvus" "run" "standalone"];
              env = [
                { name = "ETCD_USE_EMBED"; value = "true"; }
                { name = "COMMON_STORAGETYPE"; value = "local"; }
              ];
              volumeMounts = [{
                name = "data";
                mountPath = "/var/lib/milvus";
              }];
              resources = {
                requests = {
                  cpu = "500m";
                  memory = "2Gi";
                };
                limits = {
                  memory = "4Gi";
                };
              };
            }];
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "20Gi";
            };
          }];
        };
      };

      services.milvus = {
        metadata = {
          inherit namespace;
          labels.app = "milvus";
        };
        spec = {
          ports = [
            { name = "grpc"; port = 19530; targetPort = "grpc"; }
            { name = "metrics"; port = 9091; targetPort = "metrics"; }
          ];
          selector.app = "milvus";
        };
      };
    };
  };

  # CAIPE Neo4j (Graph Database)
  applications.caipe-neo4j = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      statefulSets.neo4j = {
        metadata = {
          inherit namespace;
          labels = {
            app = "neo4j";
            tier = "storage";
          };
        };
        spec = {
          replicas = 1;
          serviceName = "neo4j";
          selector.matchLabels.app = "neo4j";

          template = {
            metadata.labels.app = "neo4j";

            spec = {
              containers = [{
                name = "neo4j";
                image = "neo4j:5.26.0-community";
                ports = [
                  { containerPort = 7474; name = "http"; }
                  { containerPort = 7687; name = "bolt"; }
                ];
                env = [
                  { name = "NEO4J_AUTH"; valueFrom.secretKeyRef = { name = "neo4j-secret"; key = "NEO4J_AUTH"; }; }
                  { name = "NEO4J_PLUGINS"; value = "[\"apoc\"]"; }
                ];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/data";
                }];
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                  limits = {
                    memory = "2Gi";
                  };
                };
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "10Gi";
            };
          }];
        };
      };

      services.neo4j = {
        metadata = {
          inherit namespace;
          labels.app = "neo4j";
        };
        spec = {
          ports = [
            { name = "http"; port = 7474; targetPort = "http"; }
            { name = "bolt"; port = 7687; targetPort = "bolt"; }
          ];
          selector.app = "neo4j";
        };
      };
    };
  };

  # CAIPE Redis (Cache)
  applications.caipe-redis = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      statefulSets.redis = {
        metadata = {
          inherit namespace;
          labels = {
            app = "caipe-redis";
            tier = "storage";
          };
        };
        spec = {
          replicas = 1;
          serviceName = "redis";
          selector.matchLabels.app = "caipe-redis";

          template = {
            metadata.labels.app = "caipe-redis";

            spec.containers = [{
              name = "redis";
              image = "redis:7-alpine";
              ports = [{ containerPort = 6379; name = "redis"; }];
              volumeMounts = [{
                name = "data";
                mountPath = "/data";
              }];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  memory = "256Mi";
                };
              };
            }];
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "1Gi";
            };
          }];
        };
      };

      services.redis = {
        metadata = {
          inherit namespace;
          labels.app = "caipe-redis";
        };
        spec = {
          ports = [{ name = "redis"; port = 6379; targetPort = "redis"; }];
          selector.app = "caipe-redis";
        };
      };
    };
  };

  # =========================================================================
  # RAG Tier
  # =========================================================================

  # CAIPE RAG Server
  applications.caipe-rag-server = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "0";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.rag-server = {
        metadata = {
          inherit namespace;
          labels = {
            app = "rag-server";
            tier = "rag";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "rag-server";

          template = {
            metadata.labels.app = "rag-server";

            spec = {
              containers = [{
                name = "rag-server";
                image = "ghcr.io/pittampalliorg/rag-server:latest";
                ports = [{ containerPort = 8000; name = "http"; }];
                env = [
                  { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "llm-secret"; key = "OPENAI_API_KEY"; }; }
                  { name = "MILVUS_HOST"; value = "milvus.${namespace}.svc.cluster.local"; }
                  { name = "MILVUS_PORT"; value = "19530"; }
                ];
                resources = {
                  requests = {
                    cpu = "200m";
                    memory = "512Mi";
                  };
                  limits = {
                    memory = "1Gi";
                  };
                };
              }];
            };
          };
        };
      };

      services.rag-server = {
        metadata = {
          inherit namespace;
          labels.app = "rag-server";
        };
        spec = {
          ports = [{ name = "http"; port = 8000; targetPort = "http"; }];
          selector.app = "rag-server";
        };
      };
    };
  };

  # CAIPE RAG WebUI
  applications.caipe-rag-webui = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "0";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.rag-webui = {
        metadata = {
          inherit namespace;
          labels = {
            app = "rag-webui";
            tier = "rag";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "rag-webui";

          template = {
            metadata.labels.app = "rag-webui";

            spec.containers = [{
              name = "rag-webui";
              image = "ghcr.io/pittampalliorg/rag-webui:latest";
              ports = [{ containerPort = 3000; name = "http"; }];
              env = [
                { name = "RAG_SERVER_URL"; value = "http://rag-server.${namespace}.svc.cluster.local:8000"; }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  memory = "512Mi";
                };
              };
            }];
          };
        };
      };

      services.rag-webui = {
        metadata = {
          inherit namespace;
          labels.app = "rag-webui";
        };
        spec = {
          ports = [{ name = "http"; port = 3000; targetPort = "http"; }];
          selector.app = "rag-webui";
        };
      };

      ingresses.rag-webui = {
        metadata = {
          inherit namespace;
          annotations = {
            "nginx.ingress.kubernetes.io/use-regex" = "true";
            "nginx.ingress.kubernetes.io/rewrite-target" = "/$2";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = ingressHost;
            http.paths = [{
              path = "/rag(/|$)(.*)";
              pathType = "ImplementationSpecific";
              backend.service = {
                name = "rag-webui";
                port.name = "http";
              };
            }];
          }];
        };
      };
    };
  };

  # CAIPE RAG Ingestors
  applications.caipe-rag-ingestors = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "0";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.rag-ingestors = {
        metadata = {
          inherit namespace;
          labels = {
            app = "rag-ingestors";
            tier = "rag";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "rag-ingestors";

          template = {
            metadata.labels.app = "rag-ingestors";

            spec.containers = [{
              name = "rag-ingestors";
              image = "ghcr.io/pittampalliorg/rag-ingestors:latest";
              env = [
                { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "embeddings-secret"; key = "OPENAI_API_KEY"; }; }
                { name = "NEO4J_URI"; value = "bolt://neo4j.${namespace}.svc.cluster.local:7687"; }
                { name = "NEO4J_AUTH"; valueFrom.secretKeyRef = { name = "neo4j-secret"; key = "NEO4J_AUTH"; }; }
                { name = "MILVUS_HOST"; value = "milvus.${namespace}.svc.cluster.local"; }
                { name = "MILVUS_PORT"; value = "19530"; }
              ];
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                limits = {
                  memory = "1Gi";
                };
              };
            }];
          };
        };
      };
    };
  };

  # CAIPE RAG K8s Ingestor
  applications.caipe-rag-k8s-ingestor = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "10";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      serviceAccounts.k8s-ingestor = {
        metadata.namespace = namespace;
      };

      clusterRoleBindings.caipe-k8s-ingestor-reader = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "view";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "k8s-ingestor";
          inherit namespace;
        }];
      };

      deployments.k8s-ingestor = {
        metadata = {
          inherit namespace;
          labels = {
            app = "k8s-ingestor";
            tier = "rag";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "k8s-ingestor";

          template = {
            metadata.labels.app = "k8s-ingestor";

            spec = {
              serviceAccountName = "k8s-ingestor";
              containers = [{
                name = "k8s-ingestor";
                image = "ghcr.io/pittampalliorg/rag-k8s-ingestor:latest";
                env = [
                  { name = "CLUSTER_NAME"; value = clusterId; }
                  { name = "SYNC_INTERVAL"; value = "3600"; }
                  { name = "RESOURCE_LIST"; value = "Deployment,Service,Ingress,Namespace,ConfigMap,StatefulSet,DaemonSet,CronJob,Job,Pod"; }
                  { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "embeddings-secret"; key = "OPENAI_API_KEY"; }; }
                  { name = "NEO4J_URI"; value = "bolt://neo4j.${namespace}.svc.cluster.local:7687"; }
                  { name = "NEO4J_AUTH"; valueFrom.secretKeyRef = { name = "neo4j-secret"; key = "NEO4J_AUTH"; }; }
                  { name = "MILVUS_HOST"; value = "milvus.${namespace}.svc.cluster.local"; }
                  { name = "MILVUS_PORT"; value = "19530"; }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    memory = "512Mi";
                  };
                };
              }];
            };
          };
        };
      };
    };
  };

  # CAIPE Nexigraph (GraphRAG)
  applications.caipe-nexigraph = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "0";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.nexigraph = {
        metadata = {
          inherit namespace;
          labels = {
            app = "nexigraph";
            tier = "rag";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "nexigraph";

          template = {
            metadata.labels.app = "nexigraph";

            spec.containers = [{
              name = "nexigraph";
              image = "ghcr.io/pittampalliorg/nexigraph:latest";
              ports = [{ containerPort = 8000; name = "http"; }];
              env = [
                { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "llm-secret"; key = "OPENAI_API_KEY"; }; }
                { name = "NEO4J_URI"; value = "bolt://neo4j.${namespace}.svc.cluster.local:7687"; }
                { name = "NEO4J_AUTH"; valueFrom.secretKeyRef = { name = "neo4j-secret"; key = "NEO4J_AUTH"; }; }
              ];
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                limits = {
                  memory = "1Gi";
                };
              };
            }];
          };
        };
      };

      services.nexigraph = {
        metadata = {
          inherit namespace;
          labels.app = "nexigraph";
        };
        spec = {
          ports = [{ name = "http"; port = 8000; targetPort = "http"; }];
          selector.app = "nexigraph";
        };
      };
    };
  };

  # =========================================================================
  # Agent Tier
  # =========================================================================

  # CAIPE Supervisor Agent
  applications.caipe-supervisor = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.supervisor = {
        metadata = {
          inherit namespace;
          labels = {
            app = "supervisor";
            tier = "agent";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "supervisor";

          template = {
            metadata.labels.app = "supervisor";

            spec.containers = [{
              name = "supervisor";
              image = "ghcr.io/pittampalliorg/caipe-supervisor:latest";
              ports = [{ containerPort = 8000; name = "http"; }];
              env = [
                { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "llm-secret"; key = "OPENAI_API_KEY"; }; }
                { name = "ANTHROPIC_API_KEY"; valueFrom.secretKeyRef = { name = "llm-secret"; key = "ANTHROPIC_API_KEY"; }; }
                { name = "RAG_SERVER_URL"; value = "http://rag-server.${namespace}.svc.cluster.local:8000"; }
                { name = "ENABLE_RAG_AGENT"; value = "true"; }
              ];
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                limits = {
                  memory = "1Gi";
                };
              };
            }];
          };
        };
      };

      services.supervisor = {
        metadata = {
          inherit namespace;
          labels.app = "supervisor";
        };
        spec = {
          ports = [{ name = "http"; port = 8000; targetPort = "http"; }];
          selector.app = "supervisor";
        };
      };

      ingresses.supervisor = {
        metadata = {
          inherit namespace;
          annotations = {
            "nginx.ingress.kubernetes.io/use-regex" = "true";
            "nginx.ingress.kubernetes.io/rewrite-target" = "/$2";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = ingressHost;
            http.paths = [{
              path = "/caipe(/|$)(.*)";
              pathType = "ImplementationSpecific";
              backend.service = {
                name = "supervisor";
                port.name = "http";
              };
            }];
          }];
        };
      };
    };
  };

  # CAIPE ArgoCD Agent
  applications.caipe-agent-argocd = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "100";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.agent-argocd = {
        metadata = {
          inherit namespace;
          labels = {
            app = "agent-argocd";
            tier = "agent";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "agent-argocd";

          template = {
            metadata.labels.app = "agent-argocd";

            spec.containers = [{
              name = "agent-argocd";
              image = "ghcr.io/pittampalliorg/caipe-agent-argocd:latest";
              ports = [{ containerPort = 8000; name = "http"; }];
              env = [
                { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "llm-secret"; key = "OPENAI_API_KEY"; }; }
                { name = "ARGOCD_AUTH_TOKEN"; valueFrom.secretKeyRef = { name = "agent-argocd-secret"; key = "ARGOCD_AUTH_TOKEN"; }; }
                { name = "ARGOCD_SERVER"; value = "argocd-server.argocd.svc.cluster.local"; }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  memory = "512Mi";
                };
              };
            }];
          };
        };
      };

      services.agent-argocd = {
        metadata = {
          inherit namespace;
          labels.app = "agent-argocd";
        };
        spec = {
          ports = [{ name = "http"; port = 8000; targetPort = "http"; }];
          selector.app = "agent-argocd";
        };
      };
    };
  };

  # CAIPE GitHub Agent
  applications.caipe-agent-github = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "100";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.agent-github = {
        metadata = {
          inherit namespace;
          labels = {
            app = "agent-github";
            tier = "agent";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "agent-github";

          template = {
            metadata.labels.app = "agent-github";

            spec.containers = [{
              name = "agent-github";
              image = "ghcr.io/pittampalliorg/caipe-agent-github:latest";
              ports = [{ containerPort = 8000; name = "http"; }];
              env = [
                { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "llm-secret"; key = "OPENAI_API_KEY"; }; }
                { name = "GITHUB_TOKEN"; valueFrom.secretKeyRef = { name = "agent-github-secret"; key = "GITHUB_TOKEN"; }; }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  memory = "512Mi";
                };
              };
            }];
          };
        };
      };

      services.agent-github = {
        metadata = {
          inherit namespace;
          labels.app = "agent-github";
        };
        spec = {
          ports = [{ name = "http"; port = 8000; targetPort = "http"; }];
          selector.app = "agent-github";
        };
      };
    };
  };

  # CAIPE Backstage Agent
  applications.caipe-agent-backstage = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "100";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.agent-backstage = {
        metadata = {
          inherit namespace;
          labels = {
            app = "agent-backstage";
            tier = "agent";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "agent-backstage";

          template = {
            metadata.labels.app = "agent-backstage";

            spec.containers = [{
              name = "agent-backstage";
              image = "ghcr.io/pittampalliorg/caipe-agent-backstage:latest";
              ports = [{ containerPort = 8000; name = "http"; }];
              env = [
                { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = "llm-secret"; key = "OPENAI_API_KEY"; }; }
                { name = "BACKSTAGE_API_TOKEN"; valueFrom.secretKeyRef = { name = "agent-backstage-secret"; key = "BACKSTAGE_API_TOKEN"; }; }
                { name = "BACKSTAGE_URL"; value = "http://backstage.backstage.svc.cluster.local:7007"; }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  memory = "512Mi";
                };
              };
            }];
          };
        };
      };

      services.agent-backstage = {
        metadata = {
          inherit namespace;
          labels.app = "agent-backstage";
        };
        spec = {
          ports = [{ name = "http"; port = 8000; targetPort = "http"; }];
          selector.app = "agent-backstage";
        };
      };
    };
  };

  # CAIPE ServiceMonitor (Prometheus metrics)
  applications.caipe-servicemonitor = lib.mkIf isKind {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "110";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    yamls = [
      ''
        apiVersion: monitoring.coreos.com/v1
        kind: ServiceMonitor
        metadata:
          name: caipe-metrics
          namespace: ${namespace}
          labels:
            app: caipe
        spec:
          selector:
            matchLabels:
              tier: agent
          endpoints:
            - port: http
              path: /metrics
              interval: 30s
      ''
    ];
  };

  # CAIPE Tailscale Serve
  applications.caipe-tailscale-serve = lib.mkIf isKind {
    namespace = "tailscale";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-55";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      persistentVolumeClaims."caipe${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."caipe${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "caipe-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "caipe-tailscale-serve";

          template = {
            metadata.labels.app = "caipe-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.82.0";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "caipe${clusterSuffix}"; }
                  { name = "TS_SERVE_CONFIG"; value = "/config/serve.json"; }
                  { name = "TS_STATE_DIR"; value = "/var/lib/tailscale"; }
                ];
                volumeMounts = [
                  { name = "state"; mountPath = "/var/lib/tailscale"; }
                  { name = "config"; mountPath = "/config"; }
                ];
              }];

              volumes = [
                {
                  name = "state";
                  persistentVolumeClaim.claimName = "caipe${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "caipe-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.caipe-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "caipe${clusterSuffix}.tail286401.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://supervisor.${namespace}.svc.cluster.local:8000";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
