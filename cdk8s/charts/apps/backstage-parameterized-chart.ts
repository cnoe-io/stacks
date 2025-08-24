import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import * as images from '../../../.env-files/images.json';

export interface BackstageParameterizedChartProps extends ChartProps {
  environmentName: string;
}

/**
 * Creates Backstage application resources for a specific environment
 * Generates complete manifests with environment-specific images
 */
export class BackstageParameterizedChart extends Chart {
  constructor(scope: Construct, id: string, props: BackstageParameterizedChartProps) {
    super(scope, id, props);

    const envName = props.environmentName;
    const namespace = 'backstage';
    
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

    // PostgreSQL Service (each environment gets its own database)
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

    // Backstage Deployment
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
                // Dev containers sleep by default for development
                ...(envName === 'dev' ? { command: ['sleep', 'infinity'] } : {}),
                env: [
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
                  {
                    name: 'ENVIRONMENT',
                    value: envName
                  },
                  {
                    name: 'POSTGRES_HOST',
                    value: `postgresql-${envName}`
                  },
                  {
                    name: 'POSTGRES_PORT',
                    value: '5432'
                  },
                  {
                    name: 'POSTGRES_USER',
                    value: 'backstage'
                  },
                  {
                    name: 'POSTGRES_PASSWORD',
                    value: envName === 'dev' ? 'backstage' : 'changeme123'
                  },
                  {
                    name: 'POSTGRES_DB',
                    value: `backstage_${envName}`
                  },
                  {
                    name: 'APP_CONFIG_app_baseUrl',
                    value: envName === 'dev' ? 'https://cnoe.localtest.me:8443' : `https://backstage-${envName}.cnoe.localtest.me:8443`
                  },
                  {
                    name: 'APP_CONFIG_backend_baseUrl',
                    value: envName === 'dev' ? 'https://cnoe.localtest.me:8443' : `https://backstage-${envName}.cnoe.localtest.me:8443`
                  },
                  {
                    name: 'APP_CONFIG_backend_cors_origin',
                    value: envName === 'dev' ? 'https://cnoe.localtest.me:8443' : `https://backstage-${envName}.cnoe.localtest.me:8443`
                  }
                ],
                ports: [
                  {
                    name: 'http',
                    containerPort: 7007,
                    protocol: 'TCP'
                  }
                ],
                volumeMounts: [
                  {
                    name: 'k8s-config',
                    mountPath: '/app/k8s-config.yaml',
                    subPath: 'k8s-config.yaml'
                  }
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString(envName === 'dev' ? '2' : '200m'),
                    memory: k8s.Quantity.fromString(envName === 'dev' ? '8Gi' : '512Mi')
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString(envName === 'dev' ? '8' : '1000m'),
                    memory: k8s.Quantity.fromString(envName === 'dev' ? '32Gi' : '2Gi')
                  }
                },
                imagePullPolicy: 'Always',
                // Only add health probes for non-dev environments
                ...(envName !== 'dev' ? {
                  livenessProbe: {
                    httpGet: {
                      path: '/healthcheck',
                      port: k8s.IntOrString.fromNumber(7007)
                    },
                    initialDelaySeconds: 60,
                    periodSeconds: 10,
                    timeoutSeconds: 5
                  },
                  readinessProbe: {
                    httpGet: {
                      path: '/healthcheck',
                      port: k8s.IntOrString.fromNumber(7007)
                    },
                    initialDelaySeconds: 30,
                    periodSeconds: 10,
                    timeoutSeconds: 5
                  }
                } : {})
              }
            ],
            volumes: [
              {
                name: 'k8s-config',
                secret: {
                  secretName: `k8s-config-${envName}`
                }
              }
            ]
          }
        }
      }
    });

    // Ingress (for external access)
    new k8s.KubeIngress(this, `${envName}-backstage-ingress`, {
      metadata: {
        name: `backstage-ingress-${envName}`,
        namespace: namespace,
        labels: {
          app: `backstage-${envName}`,
          environment: envName,
        },
        annotations: {
          'nginx.ingress.kubernetes.io/force-ssl-redirect': 'false',
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          'argocd.argoproj.io/sync-wave': '30'
        }
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [
          {
            host: envName === 'dev' ? 'cnoe.localtest.me' : `backstage-${envName}.cnoe.localtest.me`,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: `backstage-${envName}`,
                      port: {
                        number: 7007
                      }
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    });
  }
}