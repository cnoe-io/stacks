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
        apiVersion: external-secrets.io/v1
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
            # LLM Provider selection (azure-openai, openai, etc.)
            - secretKey: LLM_PROVIDER
              remoteRef:
                key: CAIPE-LLM-PROVIDER
            # Azure OpenAI credentials
            - secretKey: AZURE_OPENAI_API_KEY
              remoteRef:
                key: AZURE-OPENAI-API-KEY
            - secretKey: AZURE_OPENAI_ENDPOINT
              remoteRef:
                key: AZURE-OPENAI-ENDPOINT
            - secretKey: AZURE_OPENAI_API_VERSION
              remoteRef:
                key: AZURE-OPENAI-API-VERSION
            - secretKey: OPENAI_API_VERSION
              remoteRef:
                key: AZURE-OPENAI-API-VERSION
            - secretKey: AZURE_OPENAI_DEPLOYMENT
              remoteRef:
                key: AZURE-OPENAI-DEPLOYMENT
            # Fallback OpenAI/Anthropic keys
            - secretKey: OPENAI_API_KEY
              remoteRef:
                key: OPENAI-API-KEY
            - secretKey: ANTHROPIC_API_KEY
              remoteRef:
                key: ANTHROPIC-API-KEY
      ''
      ''
        apiVersion: external-secrets.io/v1
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
      # neo4j-secret - uses template to set both NEO4J_AUTH and NEO4J_PASSWORD
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: neo4j-secret
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: caipe
            app.kubernetes.io/component: neo4j
            app.kubernetes.io/part-of: ai-platform-engineering
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: neo4j-secret
            creationPolicy: Owner
            template:
              type: Opaque
              data:
                NEO4J_AUTH: "neo4j/{{ .password }}"
                NEO4J_PASSWORD: "{{ .password }}"
          data:
            - secretKey: password
              remoteRef:
                key: CAIPE-NEO4J-PASSWORD
      ''
      ''
        apiVersion: external-secrets.io/v1
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
        apiVersion: external-secrets.io/v1
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
        apiVersion: external-secrets.io/v1
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
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: ghcr-pull-secret
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: ghcr-pull-secret
            creationPolicy: Owner
            template:
              type: kubernetes.io/dockerconfigjson
              data:
                .dockerconfigjson: |
                  {"auths":{"ghcr.io":{"username":"pittampalliorg","password":"{{ .token }}","auth":"{{ printf "%s:%s" "pittampalliorg" .token | b64enc }}"}}}
          data:
            - secretKey: token
              remoteRef:
                key: GITHUB-PAT
      ''
    ];
  };

  # CAIPE Token Sync (ArgoCD token synchronization)
  # Creates token, stores in K8s secret, then pushes to Azure Key Vault
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

    resources = {
      # ServiceAccount for token generator
      serviceAccounts.caipe-token-generator = {
        metadata.namespace = "argocd";
      };

      # Role for creating secrets
      roles.caipe-token-generator = {
        metadata.namespace = "argocd";
        rules = [{
          apiGroups = [ "" ];
          resources = [ "secrets" ];
          verbs = [ "create" "update" "patch" "get" ];
        }];
      };

      # RoleBinding
      roleBindings.caipe-token-generator = {
        metadata.namespace = "argocd";
        subjects = [{
          kind = "ServiceAccount";
          name = "caipe-token-generator";
          namespace = "argocd";
        }];
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "caipe-token-generator";
        };
      };
    };

    yamls = [
      # Job - Generate ArgoCD token and store in K8s secret
      ''
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: caipe-token-generator
          namespace: argocd
          annotations:
            argocd.argoproj.io/sync-wave: "50"
            argocd.argoproj.io/hook: Sync
            argocd.argoproj.io/hook-delete-policy: HookSucceeded
        spec:
          ttlSecondsAfterFinished: 300
          backoffLimit: 3
          template:
            spec:
              serviceAccountName: caipe-token-generator
              restartPolicy: OnFailure
              containers:
                - name: token-generator
                  image: bitnami/kubectl:latest
                  command: ["/bin/bash", "-c"]
                  env:
                    - name: HOME
                      value: /tmp
                  args:
                    - |
                      set -e

                      # Install argocd CLI
                      echo "Installing ArgoCD CLI..."
                      curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v2.11.0/argocd-linux-amd64
                      chmod +x /tmp/argocd

                      echo "Checking if ArgoCD token secret already exists..."

                      # Check if the secret already exists and has a valid token
                      EXISTING_TOKEN=$(kubectl get secret caipe-argocd-token -n argocd -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")

                      if [ -n "$EXISTING_TOKEN" ]; then
                        echo "Token secret already exists. Validating token..."
                        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
                          -H "Authorization: Bearer $EXISTING_TOKEN" \
                          "https://argocd-server.argocd/api/v1/account" \
                          --insecure 2>/dev/null || echo "000")

                        if [ "$RESPONSE" = "200" ]; then
                          echo "Existing token is valid. Skipping regeneration."
                          exit 0
                        fi
                        echo "Existing token is invalid (HTTP $RESPONSE). Regenerating..."
                      fi

                      echo "Generating new ArgoCD API token for account 'developer'..."

                      # Get admin password from secret
                      ADMIN_PASSWORD=$(cat /var/run/secrets/argocd/password)

                      # Login to ArgoCD
                      /tmp/argocd login argocd-server.argocd \
                        --username admin \
                        --password "$ADMIN_PASSWORD" \
                        --insecure \
                        --grpc-web

                      # Generate token for the target account
                      TOKEN=$(/tmp/argocd account generate-token --account developer)

                      if [ -z "$TOKEN" ]; then
                        echo "ERROR: Failed to generate token"
                        exit 1
                      fi

                      echo "Token generated successfully"

                      # Create or update the Kubernetes secret
                      cat <<EOF | kubectl apply -f -
                      apiVersion: v1
                      kind: Secret
                      metadata:
                        name: caipe-argocd-token
                        namespace: argocd
                      type: Opaque
                      stringData:
                        token: "$TOKEN"
                      EOF

                      echo "Secret 'caipe-argocd-token' created/updated successfully"
                  volumeMounts:
                    - name: argocd-admin-password
                      mountPath: /var/run/secrets/argocd
                      readOnly: true
              volumes:
                - name: argocd-admin-password
                  secret:
                    secretName: argocd-initial-admin-secret
                    items:
                      - key: password
                        path: password
      ''
      # PushSecret - Sync the K8s secret to Azure Key Vault
      ''
        apiVersion: external-secrets.io/v1alpha1
        kind: PushSecret
        metadata:
          name: caipe-argocd-token-push
          namespace: argocd
          annotations:
            argocd.argoproj.io/sync-wave: "51"
        spec:
          refreshInterval: 1h
          updatePolicy: Replace
          deletionPolicy: None
          secretStoreRefs:
            - name: azure-keyvault-store
              kind: ClusterSecretStore
          selector:
            secret:
              name: caipe-argocd-token
          data:
            - match:
                secretKey: token
                remoteRef:
                  remoteKey: CAIPE-ARGOCD-TOKEN-${lib.toUpper clusterId}
      ''
    ];
  };

  # Backstage API Token Sync - Generate token for CAIPE agents to call Backstage APIs
  applications.backstage-api-token-sync = lib.mkIf isKind {
    namespace = "backstage";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-20";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    yamls = [
      # ServiceAccount for token generator (must exist before Job runs)
      ''
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: backstage-token-generator
          namespace: backstage
          annotations:
            argocd.argoproj.io/sync-wave: "-21"
      ''
      # Role for creating secrets
      ''
        apiVersion: rbac.authorization.k8s.io/v1
        kind: Role
        metadata:
          name: backstage-token-generator
          namespace: backstage
          annotations:
            argocd.argoproj.io/sync-wave: "-21"
        rules:
          - apiGroups: [""]
            resources: ["secrets"]
            verbs: ["create", "update", "patch", "get"]
      ''
      # RoleBinding
      ''
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        metadata:
          name: backstage-token-generator
          namespace: backstage
          annotations:
            argocd.argoproj.io/sync-wave: "-21"
        subjects:
          - kind: ServiceAccount
            name: backstage-token-generator
            namespace: backstage
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: Role
          name: backstage-token-generator
      ''
      # Job - Generate Backstage API token and store in K8s secret
      ''
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: backstage-token-generator
          namespace: backstage
          annotations:
            argocd.argoproj.io/sync-wave: "-20"
            argocd.argoproj.io/hook: Sync
            argocd.argoproj.io/hook-delete-policy: HookSucceeded
        spec:
          ttlSecondsAfterFinished: 300
          backoffLimit: 3
          template:
            spec:
              serviceAccountName: backstage-token-generator
              restartPolicy: OnFailure
              containers:
                - name: token-generator
                  image: bitnami/kubectl:latest
                  command: ["/bin/bash", "-c"]
                  args:
                    - |
                      set -e

                      echo "Checking if Backstage API token secret already exists..."

                      # Check if the secret already exists and has a valid token
                      EXISTING_TOKEN=$(kubectl get secret backstage-api-token -n backstage -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")

                      if [ -n "$EXISTING_TOKEN" ] && [ "''${#EXISTING_TOKEN}" -gt 20 ]; then
                        echo "Token secret already exists with valid token (length: ''${#EXISTING_TOKEN}). Skipping regeneration."
                        exit 0
                      fi

                      echo "Generating new Backstage API token..."

                      # Generate a cryptographically secure random token (32 bytes = 256 bits)
                      TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '\n')

                      if [ -z "$TOKEN" ] || [ "''${#TOKEN}" -lt 20 ]; then
                        echo "ERROR: Failed to generate token"
                        exit 1
                      fi

                      echo "Token generated successfully (length: ''${#TOKEN})"

                      # Create or update the Kubernetes secret
                      cat <<EOF | kubectl apply -f -
                      apiVersion: v1
                      kind: Secret
                      metadata:
                        name: backstage-api-token
                        namespace: backstage
                        labels:
                          app.kubernetes.io/name: backstage-token-sync
                          app.kubernetes.io/component: api-token
                          app.kubernetes.io/part-of: backstage
                      type: Opaque
                      stringData:
                        token: "$TOKEN"
                      EOF

                      echo "Secret 'backstage-api-token' created/updated successfully"
      ''
      # PushSecret - Sync the K8s secret to Azure Key Vault
      ''
        apiVersion: external-secrets.io/v1alpha1
        kind: PushSecret
        metadata:
          name: backstage-api-token-push
          namespace: backstage
          annotations:
            argocd.argoproj.io/sync-wave: "-19"
        spec:
          refreshInterval: 1h
          updatePolicy: Replace
          deletionPolicy: None
          secretStoreRefs:
            - name: azure-keyvault-store
              kind: ClusterSecretStore
          selector:
            secret:
              name: backstage-api-token
          data:
            - match:
                secretKey: token
                remoteRef:
                  remoteKey: CAIPE-BACKSTAGE-API-TOKEN-${lib.toUpper clusterId}
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
              # Use v2.4.x to fix HNSW index efConstruction bug (pymilvus #1886)
              image = "milvusdb/milvus:v2.4.17";
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
                  # Disable strict config validation to ignore K8s service discovery env vars
                  { name = "NEO4J_server_config_strict__validation_enabled"; value = "false"; }
                  # Memory settings - must fit within 2Gi container limit
                  { name = "NEO4J_server_memory_heap_initial__size"; value = "1g"; }
                  { name = "NEO4J_server_memory_heap_max__size"; value = "1g"; }
                  { name = "NEO4J_server_memory_pagecache_size"; value = "512m"; }
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
          # Scaled to 0 - langchain-milvus has bug with HNSW index params (pymilvus #1886)
          # Error: "efConstruction out of range" when creating sparse-dense vector index
          # Fix: Update caipe-rag-server image when langchain-milvus is fixed upstream
          replicas = 0;
          selector.matchLabels.app = "rag-server";

          template = {
            metadata.labels.app = "rag-server";

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "rag-server";
                image = "ghcr.io/cnoe-io/caipe-rag-server:0.2.8";
                ports = [{ containerPort = 8000; name = "http"; }];
                env = [
                  # Use MILVUS_URI format as expected by rag-server
                  { name = "MILVUS_URI"; value = "http://milvus.${namespace}.svc.cluster.local:19530"; }
                  # Neo4j connection for GraphRAG
                  { name = "NEO4J_ADDR"; value = "neo4j://neo4j.${namespace}.svc.cluster.local:7687"; }
                  { name = "NEO4J_ONTOLOGY_ADDR"; value = "neo4j://neo4j.${namespace}.svc.cluster.local:7687"; }
                  { name = "NEO4J_USERNAME"; value = "neo4j"; }
                  # Redis for caching
                  { name = "REDIS_URL"; value = "redis://redis.${namespace}.svc.cluster.local:6379/0"; }
                  # Agent ontology for GraphRAG
                  { name = "ONTOLOGY_AGENT_RESTAPI_ADDR"; value = "http://nexigraph.${namespace}.svc.cluster.local:8098"; }
                  # Embedding model
                  { name = "EMBEDDINGS_MODEL"; value = "text-embedding-3-large"; }
                  { name = "ENABLE_GRAPH_RAG"; value = "true"; }
                ];
                # Inject all keys from secrets
                envFrom = [
                  { secretRef.name = "llm-secret"; }
                  { secretRef.name = "embeddings-secret"; }
                  { secretRef.name = "neo4j-secret"; }
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

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "rag-webui";
                image = "ghcr.io/cnoe-io/caipe-rag-webui:0.2.8";
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
          # Scaled to 0 - image has entry point bug (double slash in path)
          replicas = 0;
          selector.matchLabels.app = "rag-ingestors";

          template = {
            metadata.labels.app = "rag-ingestors";

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "rag-ingestors";
                image = "ghcr.io/cnoe-io/caipe-rag-ingestors:latest";
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
          # Scaled to 0 - same image issue as rag-ingestors
          replicas = 0;
          selector.matchLabels.app = "k8s-ingestor";

          template = {
            metadata.labels.app = "k8s-ingestor";

            spec = {
              serviceAccountName = "k8s-ingestor";
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "k8s-ingestor";
                image = "ghcr.io/cnoe-io/caipe-rag-ingestors:latest";
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

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "nexigraph";
                image = "ghcr.io/cnoe-io/caipe-rag-agent-ontology:0.2.8";
                ports = [{ containerPort = 8000; name = "http"; }];
                env = [
                  # Neo4j connection (use NEO4J_ADDR format, not NEO4J_URI)
                  { name = "NEO4J_ADDR"; value = "neo4j://neo4j.${namespace}.svc.cluster.local:7687"; }
                  { name = "NEO4J_ONTOLOGY_ADDR"; value = "neo4j://neo4j.${namespace}.svc.cluster.local:7687"; }
                  { name = "NEO4J_USERNAME"; value = "neo4j"; }
                  { name = "REDIS_URL"; value = "redis://redis.${namespace}.svc.cluster.local:6379/0"; }
                ];
                envFrom = [
                  { secretRef.name = "llm-secret"; }
                  { secretRef.name = "neo4j-secret"; }
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

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "supervisor";
                image = "ghcr.io/cnoe-io/ai-platform-engineering:latest";
                # Run the platform-engineer multi-agent system
                command = ["python" "-m" "ai_platform_engineering.multi_agents" "platform-engineer"];
                ports = [{ containerPort = 8000; name = "http"; }];
                env = [
                  { name = "RAG_SERVER_URL"; value = "http://rag-server.${namespace}.svc.cluster.local:8000"; }
                  { name = "ENABLE_RAG_AGENT"; value = "true"; }
                ];
                # Inject all LLM keys from secret (includes LLM_PROVIDER, AZURE_OPENAI_*, etc.)
                envFrom = [
                  { secretRef.name = "llm-secret"; }
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

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "agent-argocd";
                image = "ghcr.io/cnoe-io/agent-argocd:latest";
                ports = [{ containerPort = 8000; name = "http"; }];
                env = [
                  { name = "ARGOCD_SERVER"; value = "argocd-server.argocd.svc.cluster.local"; }
                ];
                envFrom = [
                  { secretRef.name = "llm-secret"; }
                  { secretRef.name = "agent-argocd-secret"; }
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

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "agent-github";
                image = "ghcr.io/cnoe-io/agent-github:latest";
                ports = [{ containerPort = 8000; name = "http"; }];
                # Use envFrom to inject all keys from secrets
                envFrom = [
                  { secretRef.name = "llm-secret"; }
                  { secretRef.name = "agent-github-secret"; }
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

            spec = {
              imagePullSecrets = [{ name = "ghcr-pull-secret"; }];
              containers = [{
                name = "agent-backstage";
                image = "ghcr.io/cnoe-io/agent-backstage:latest";
                ports = [{ containerPort = 8000; name = "http"; }];
                env = [
                  { name = "BACKSTAGE_URL"; value = "http://backstage.backstage.svc.cluster.local:7007"; }
                ];
                # Use envFrom to inject all keys from secrets
                envFrom = [
                  { secretRef.name = "llm-secret"; }
                  { secretRef.name = "agent-backstage-secret"; }
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

    # Placeholder ConfigMap until Prometheus Operator CRDs are installed
    resources = {
      configMaps.caipe-servicemonitor-placeholder = {
        metadata = {
          namespace = namespace;
          labels = {
            "app.kubernetes.io/name" = "caipe-servicemonitor";
            "app.kubernetes.io/part-of" = "ai-platform-engineering";
          };
        };
        data = {
          status = "placeholder";
          note = "ServiceMonitor requires Prometheus Operator CRDs. Install kube-prometheus-stack to enable metrics scraping.";
        };
      };
    };
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
                  # Reset state on restart to avoid conflicts with existing Tailscale node
                  { name = "TS_EXTRA_ARGS"; value = "--reset"; }
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
