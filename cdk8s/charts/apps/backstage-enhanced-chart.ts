import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import * as crypto from 'crypto';
import * as images from '../../../.env-files/images.json';
import { DevSpaceSSHConstruct, SSHNodePortAllocator } from '../../lib/devspace-ssh-construct';
import { 
  ExternalSecret,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecDataRemoteRefConversionStrategy,
  ExternalSecretSpecDataRemoteRefDecodingStrategy,
  ExternalSecretSpecTargetTemplateEngineVersion
} from '../../imports/external-secrets.io';

export interface BackstageEnhancedChartProps extends ChartProps {
  environmentName: string;
}

/**
 * Enhanced Backstage chart with SSH and Code tunnel support
 * 
 * This chart always:
 * - Uses External Secrets from Azure Key Vault for production-ready secrets
 * - Pulls Code tunnel token from GITHUB-CODE-TUNNEL-PAT in Azure Key Vault
 * - Provides both SSH and Code tunnel access methods
 * 
 * Environment variable:
 * - BACKSTAGE_CODE_TUNNEL_ENABLED: Enable Code tunnel (default: true for dev)
 */
export class BackstageEnhancedChart extends Chart {
  private readonly tunnelName: string;

  constructor(scope: Construct, id: string, props: BackstageEnhancedChartProps) {
    super(scope, id, props);

    const envName = props.environmentName;
    const namespace = 'backstage';
    
    // Code tunnel is enabled by default for dev, can be overridden via env var
    const enableCodeTunnel = process.env.BACKSTAGE_CODE_TUNNEL_ENABLED === 'true' || 
                            (process.env.BACKSTAGE_CODE_TUNNEL_ENABLED !== 'false' && envName === 'dev');
    
    // Set tunnel name based on environment
    this.tunnelName = `backstage-${envName}-tunnel`;
    
    // Get the appropriate image for this environment
    const imageRef = images[envName as keyof typeof images]?.backstage || images.dev.backstage;
    
    // Parse image for labels
    const parseRepo = (img: string) => img.split('@')[0].split(':')[0];
    const parseTagOrDigest = (img: string) => {
      if (img.includes('@')) {
        const digest = img.split('@')[1];
        return digest.replace(':', '-');
      }
      if (img.includes(':')) {
        return img.split(':').pop() as string;
      }
      return 'latest';
    };
    const sanitizeLabel = (v: string) => v.toLowerCase().replace(/[^a-z0-9._-]/g, '-').slice(0, 63).replace(/^-+|[-.]+$/g, '');
    const imageRepoLabel = sanitizeLabel(parseRepo(imageRef));
    const imageTagLabel = sanitizeLabel(parseTagOrDigest(imageRef));

    // Service Account
    new k8s.KubeServiceAccount(this, `${envName}-backstage-sa`, {
      metadata: {
        name: `backstage-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
        }
      }
    });

    // ClusterRole for Backstage
    new k8s.KubeClusterRole(this, `${envName}-backstage-read-all`, {
      metadata: {
        name: `backstage-read-all-${envName}`,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
        }
      },
      rules: [
        {
          apiGroups: ['*'],
          resources: ['*'],
          verbs: ['get', 'list', 'watch']
        }
      ]
    });

    // ClusterRoleBinding
    new k8s.KubeClusterRoleBinding(this, `${envName}-backstage-read-all-binding`, {
      metadata: {
        name: `backstage-read-all-${envName}`,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
        }
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: `backstage-read-all-${envName}`
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: `backstage-${envName}`,
          namespace: namespace
        }
      ]
    });

    // Always use External Secrets from Azure Key Vault
    this.createExternalSecrets(envName, namespace, enableCodeTunnel);

    // Backstage Service
    new k8s.KubeService(this, `${envName}-backstage-service`, {
      metadata: {
        name: `backstage-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
        }
      },
      spec: {
        ports: [
          {
            name: 'http',
            port: 7007,
            targetPort: k8s.IntOrString.fromString('http')
          }
        ],
        selector: {
          app: `backstage-${envName}`,
          environment: envName,
        }
      }
    });

    // SSH Service using reusable construct
    new DevSpaceSSHConstruct(this, `${envName}-backstage-ssh`, {
      namespace: namespace,
      appName: 'backstage',
      environment: envName,
      nodePort: SSHNodePortAllocator.getPort('backstage', envName)
    });

    // PostgreSQL Service and StatefulSet (unchanged)
    this.createPostgreSQL(envName, namespace);

    // Kubernetes Config Secret
    new k8s.KubeSecret(this, `${envName}-k8s-config`, {
      metadata: {
        name: `k8s-config-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
        }
      },
      stringData: {
        'k8s-config.yaml': `type: 'config'
clusters:
  - url: https://kubernetes.default.svc.cluster.local
    name: ${envName}-cluster
    authProvider: 'serviceAccount'
    skipTLSVerify: true
    skipMetricsLookup: true
    serviceAccountToken: 
      $file: /var/run/secrets/kubernetes.io/serviceaccount/token
    caData: 
      $file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
      }
    });

    // Backstage Deployment with enhanced configuration
    new k8s.KubeDeployment(this, `${envName}-backstage-deployment`, {
      metadata: {
        name: `backstage-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '20'
        }
      },
      spec: {
        replicas: 1,
        strategy: {
          type: 'Recreate'
        },
        selector: {
          matchLabels: {
            app: `backstage-${envName}`,
            environment: envName,
          }
        },
        template: {
          metadata: {
            labels: {
              app: `backstage-${envName}`,
              environment: envName,
              'ssh-enabled': 'true',
              'code-tunnel-enabled': enableCodeTunnel ? 'true' : 'false',
              'app.kubernetes.io/name': 'backstage',
              'app.kubernetes.io/instance': `backstage-${envName}`,
              'app.kubernetes.io/part-of': 'backstage',
              'app.kubernetes.io/component': 'backend',
              'app.kubernetes.io/version': imageTagLabel,
              'backstage.pittampalli.org/image-repo': imageRepoLabel,
              'backstage.pittampalli.org/image-tag': imageTagLabel
            },
            annotations: {
              'backstage.pittampalli.org/image': imageRef
            }
          },
          spec: {
            serviceAccountName: `backstage-${envName}`,
            imagePullSecrets: [
              { name: 'ghcr-dockercfg' }
            ],
            containers: [
              {
                name: 'backstage',
                image: imageRef,
                env: [
                  // SSH Configuration
                  {
                    name: 'CONTAINER_SSH_ENABLED',
                    value: 'true'
                  },
                  {
                    name: 'CONTAINER_SSH_PORT',
                    value: '2222'
                  },
                  {
                    name: 'USERNAME',
                    value: 'code'
                  },
                  // Code Tunnel Configuration
                  {
                    name: 'CODE_TUNNEL_ENABLED',
                    value: enableCodeTunnel ? 'true' : 'false'
                  },
                  {
                    name: 'TUNNEL_NAME',
                    value: this.tunnelName
                  },
                  // Backstage Configuration
                  {
                    name: 'LOG_LEVEL',
                    value: envName === 'dev' ? 'debug' : 'info'
                  },
                  {
                    name: 'NODE_TLS_REJECT_UNAUTHORIZED',
                    value: '0'
                  },
                  {
                    name: 'NODE_ENV',
                    value: envName === 'dev' ? 'development' : 'production'
                  },
                  // Backend Auth Configuration
                  {
                    name: 'BACKEND_SECRET',
                    valueFrom: {
                      secretKeyRef: {
                        name: `backstage-backend-auth-${envName}`,
                        key: 'secret'
                      }
                    }
                  },
                  // Database Configuration
                  {
                    name: 'POSTGRES_SERVICE_HOST',
                    value: `postgresql-${envName}.${namespace}.svc.cluster.local`
                  },
                  {
                    name: 'POSTGRES_SERVICE_PORT',
                    value: '5432'
                  },
                  {
                    name: 'POSTGRES_USER',
                    value: 'backstage'
                  },
                  {
                    name: 'POSTGRES_PASSWORD',
                    value: envName === 'dev' ? 'backstage' : 'changeme123'
                  }
                ],
                ports: [
                  {
                    name: 'http',
                    containerPort: 7007
                  },
                  {
                    name: 'ssh',
                    containerPort: 2222
                  }
                ],
                volumeMounts: [
                  {
                    name: 'k8s-config',
                    mountPath: '/etc/backstage/k8s-config.yaml',
                    subPath: 'k8s-config.yaml'
                  },
                  {
                    name: 'ssh-keys',
                    mountPath: '/ssh-keys',
                    readOnly: true
                  },
                  {
                    name: 'ssh-host-keys',
                    mountPath: '/ssh-host-keys',
                    readOnly: true
                  },
                  ...(enableCodeTunnel ? [{
                    name: 'code-tunnel',
                    mountPath: '/code-tunnel',
                    readOnly: true
                  }] : [])
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('500m'),
                    memory: k8s.Quantity.fromString('1Gi')
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('2000m'),
                    memory: k8s.Quantity.fromString('2Gi')
                  }
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(2222)  // Check SSH port for dev container
                  },
                  initialDelaySeconds: 60,
                  periodSeconds: 30,
                  timeoutSeconds: 10
                },
                readinessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(2222)  // Check SSH port for dev container
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                  timeoutSeconds: 5
                }
              }
            ],
            volumes: [
              {
                name: 'k8s-config',
                secret: {
                  secretName: `k8s-config-${envName}`
                }
              },
              {
                name: 'ssh-keys',
                secret: {
                  secretName: `backstage-ssh-keys-${envName}`,
                  defaultMode: 0o600
                }
              },
              {
                name: 'ssh-host-keys',
                secret: {
                  secretName: `backstage-ssh-host-keys-${envName}`,
                  defaultMode: 0o600
                }
              },
              ...(enableCodeTunnel ? [{
                name: 'code-tunnel',
                secret: {
                  secretName: `backstage-code-tunnel-${envName}`,
                  defaultMode: 0o400
                }
              }] : [])
            ]
          }
        }
      }
    });
  }


  /**
   * Create External Secrets resources from Azure Key Vault
   */
  private createExternalSecrets(envName: string, namespace: string, enableCodeTunnel: boolean) {
    // Backend Auth Secret
    new ExternalSecret(this, `${envName}-backend-auth-external`, {
      metadata: {
        name: `backstage-backend-auth-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
          purpose: 'backend-auth'
        }
      },
      spec: {
        refreshInterval: '15m',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
        },
        target: {
          name: `backstage-backend-auth-${envName}`,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER
        },
        data: [
          {
            secretKey: 'secret',
            remoteRef: {
              key: 'BACKSTAGE-BACKEND-AUTH-SECRET',
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          }
        ]
      }
    });

    // SSH Keys from Azure Key Vault
    new ExternalSecret(this, `${envName}-ssh-keys-external`, {
      metadata: {
        name: `backstage-ssh-keys-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
          purpose: 'ssh-access'
        }
      },
      spec: {
        refreshInterval: '24h',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
        },
        target: {
          name: `backstage-ssh-keys-${envName}`,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER
        },
        data: [
          {
            secretKey: 'authorized_keys',
            remoteRef: {
              key: `BACKSTAGE-SSH-AUTHORIZED-KEYS-${envName.toUpperCase()}`,
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          }
        ]
      }
    });

    // SSH Host Keys from Azure Key Vault
    new ExternalSecret(this, `${envName}-ssh-host-keys-external`, {
      metadata: {
        name: `backstage-ssh-host-keys-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
          purpose: 'ssh-host-keys'
        }
      },
      spec: {
        refreshInterval: '24h',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
        },
        target: {
          name: `backstage-ssh-host-keys-${envName}`,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER
        },
        data: [
          {
            secretKey: 'ssh_host_rsa_key',
            remoteRef: {
              key: `BACKSTAGE-SSH-HOST-RSA-KEY-${envName.toUpperCase()}`,
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          },
          {
            secretKey: 'ssh_host_ed25519_key',
            remoteRef: {
              key: `BACKSTAGE-SSH-HOST-ED25519-KEY-${envName.toUpperCase()}`,
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          },
          {
            secretKey: 'ssh_host_rsa_key.pub',
            remoteRef: {
              key: `BACKSTAGE-SSH-HOST-RSA-KEY-PUB-${envName.toUpperCase()}`,
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          },
          {
            secretKey: 'ssh_host_ed25519_key.pub',
            remoteRef: {
              key: `BACKSTAGE-SSH-HOST-ED25519-KEY-PUB-${envName.toUpperCase()}`,
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          }
        ]
      }
    });

    // Code Tunnel Token from External Secrets (if enabled)
    if (enableCodeTunnel) {
      new ExternalSecret(this, `${envName}-code-tunnel-external`, {
        metadata: {
          name: `backstage-code-tunnel-${envName}`,
          namespace: namespace,
          labels: {
            app: `backstage-${envName}`,
            environment: envName,
            purpose: 'code-tunnel'
          },
          annotations: {
            'backstage.io/note': 'Uses GITHUB-CODE-TUNNEL-PAT from Azure Key Vault'
          }
        },
        spec: {
          refreshInterval: '1h',
          secretStoreRef: {
            name: 'azure-keyvault-store',
            kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
          },
          target: {
            name: `backstage-code-tunnel-${envName}`,
            creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
            template: {
              engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
              data: {
                'github_token': '{{ .token }}',
                'tunnel_name': this.tunnelName
              }
            }
          },
          data: [
            {
              secretKey: 'token',
              remoteRef: {
                // Always use the same token from Azure Key Vault for all environments
                key: 'GITHUB-CODE-TUNNEL-PAT',
                conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
              }
            }
          ]
        }
      });
    }
  }

  /**
   * Create PostgreSQL resources
   */
  private createPostgreSQL(envName: string, namespace: string) {
    // PostgreSQL Service
    new k8s.KubeService(this, `${envName}-postgresql-service`, {
      metadata: {
        name: `postgresql-${envName}`,
        namespace: namespace,
        labels: {
          app: `postgresql-${envName}`,
          environment: envName,
        }
      },
      spec: {
        ports: [
          {
            port: 5432,
            targetPort: k8s.IntOrString.fromNumber(5432)
          }
        ],
        selector: {
          app: `postgresql-${envName}`,
          environment: envName,
        },
        clusterIp: 'None'
      }
    });

    // PostgreSQL StatefulSet
    new k8s.KubeStatefulSet(this, `${envName}-postgresql`, {
      metadata: {
        name: `postgresql-${envName}`,
        namespace: namespace,
        labels: {
          app: `postgresql-${envName}`,
          environment: envName,
        }
      },
      spec: {
        serviceName: `postgresql-${envName}`,
        replicas: 1,
        selector: {
          matchLabels: {
            app: `postgresql-${envName}`,
            environment: envName,
          }
        },
        template: {
          metadata: {
            labels: {
              app: `postgresql-${envName}`,
              environment: envName,
            }
          },
          spec: {
            containers: [
              {
                name: 'postgresql',
                image: 'postgres:16',
                env: [
                  {
                    name: 'POSTGRES_DB',
                    value: `backstage_${envName}`
                  },
                  {
                    name: 'POSTGRES_USER',
                    value: 'backstage'
                  },
                  {
                    name: 'POSTGRES_PASSWORD',
                    value: envName === 'dev' ? 'backstage' : 'changeme123'
                  }
                ],
                ports: [
                  {
                    containerPort: 5432
                  }
                ],
                volumeMounts: [
                  {
                    name: 'postgres-storage',
                    mountPath: '/var/lib/postgresql/data'
                  }
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('100m'),
                    memory: k8s.Quantity.fromString('256Mi')
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('500m'),
                    memory: k8s.Quantity.fromString('512Mi')
                  }
                }
              }
            ]
          }
        },
        volumeClaimTemplates: [
          {
            metadata: {
              name: 'postgres-storage'
            },
            spec: {
              accessModes: ['ReadWriteOnce'],
              resources: {
                requests: {
                  storage: k8s.Quantity.fromString(envName === 'dev' ? '5Gi' : '10Gi')
                }
              }
            }
          }
        ]
      }
    });
  }
}