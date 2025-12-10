import { ApplicationConfig } from '../lib/idpbuilder-types';
import {
  automatedSyncWithOptions,
  externalSecretsAppSyncPolicy,
  EXTERNAL_SECRET_IGNORE_DIFFERENCES
} from '../lib/argocd-sync-builders';

/**
 * IDPBuilder application configurations
 * Add new applications here to have them automatically synthesized
 */
export const applicationConfigs: ApplicationConfig[] = [
  // ArgoCD Configuration - DISABLED
  // IDPBuilder manages ArgoCD directly. To customize ArgoCD's ConfigMap, use:
  // idpbuilder create -c argocd:/path/to/argocd-cm-override.yaml
  // See: https://cnoe.io/docs/idpbuilder/override
  //
  // If we need custom health checks, create a file with:
  // apiVersion: v1
  // kind: ConfigMap
  // metadata:
  //   name: argocd-cm
  // data:
  //   resource.customizations.health.networking.k8s.io_Ingress: |
  //     hs = {}
  //     hs.status = "Healthy"
  //     hs.message = "Ingress is always considered healthy"
  //     return hs
  /*
  {
    name: 'argocd-config',
    namespace: 'argocd',
    chart: {
      type: 'ArgoCDConfigChart'
    },
    argocd: {
      syncWave: '-110',  // Apply very early, before any applications
      labels: {
        'app.kubernetes.io/component': 'config',
        'app.kubernetes.io/part-of': 'argocd',
        'app.kubernetes.io/name': 'argocd-config'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },
  */
  {
    name: 'external-secrets-workload-identity',
    namespace: 'external-secrets',
    chart: {
      type: 'ExternalSecretsWorkloadIdentityChart'
    },
    argocd: {
      syncWave: '-90',  // After external-secrets operator installation
      labels: {
        'app.kubernetes.io/component': 'security',
        'app.kubernetes.io/part-of': 'platform',
        'app.kubernetes.io/name': 'external-secrets-workload-identity'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  {
    name: 'bootstrap-secrets',
    namespace: 'argocd',
    chart: {
      type: 'BootstrapSecretsChart'
    },
    dependencies: {
      externalSecretsWorkloadIdentity: {
        type: 'ExternalSecretsWorkloadIdentityChart'
      }
    },
    argocd: {
      syncWave: '-85',  // After external-secrets-workload-identity (-90) patches ESO for Azure auth
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'platform',
        'app.kubernetes.io/name': 'bootstrap-secrets'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },
  // Replaced with multi-env version below
  // {
  //   name: 'nextjs',
  //   namespace: 'nextjs',
  //   chart: {
  //     type: 'NextJsChart',
  //     props: {
  //       // Chart-specific properties can be added here
  //     }
  //   },
  //   argocd: {
  //     syncWave: '115',
  //     labels: {
  //       'app.kubernetes.io/component': 'frontend',
  //       'app.kubernetes.io/part-of': 'application-stack',
  //       'app.kubernetes.io/name': 'nextjs',
  //       'app.kubernetes.io/environment': 'staging'
  //     },
  //     syncPolicy: {
  //       automated: {
  //         prune: true,
  //         selfHeal: true,
  //         allowEmpty: false
  //       },
  //       syncOptions: [
  //         'CreateNamespace=true',
  //         'ServerSideApply=true',
  //         'ApplyOutOfSyncOnly=true'
  //       ],
  //       retry: {
  //         limit: 5,
  //         backoff: {
  //           duration: '5s',
  //           factor: 2,
  //           maxDuration: '3m'
  //         }
  //       }
  //     },
  //     ignoreDifferences: [
  //       {
  //         group: 'apps',
  //         kind: 'Deployment',
  //         jsonPointers: [
  //           '/spec/replicas',
  //           '/spec/template/metadata/annotations'
  //         ]
  //       },
  //       {
  //         group: '',
  //         kind: 'Service',
  //         jsonPointers: [
  //           '/spec/clusterIP',
  //           '/spec/clusterIPs'
  //         ]
  //       }
  //     ]
  //   }
  // },
  {
    name: 'postgres',
    namespace: 'nextjs',
    chart: {
      type: 'PostgresChart'
    },
    argocd: {
      syncWave: '50',
      labels: {
        'app.kubernetes.io/component': 'database',
        'app.kubernetes.io/part-of': 'data-layer',
        'app.kubernetes.io/name': 'postgres',
        'app.kubernetes.io/environment': 'host'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
    }
  },
  {
    name: 'redis',
    namespace: 'nextjs',
    chart: {
      type: 'RedisChart',
      props: {
        replicas: 1
      }
    },
    argocd: {
      syncWave: '60',
      labels: {
        'app.kubernetes.io/component': 'cache',
        'app.kubernetes.io/part-of': 'data-layer',
        'app.kubernetes.io/name': 'redis',
        'app.kubernetes.io/environment': 'host'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
    }
  },
  // Removed kargo-pipelines-namespace - namespace is created by kargo-pipelines-project chart
  {
    name: 'keycloak-headlamp-client',
    namespace: 'keycloak',
    chart: {
      type: 'KeycloakHeadlampClientChart'
    },
    argocd: {
      syncWave: '40',  // Before headlamp-keycloak-secrets
      labels: {
        'app.kubernetes.io/component': 'oidc-client',
        'app.kubernetes.io/part-of': 'keycloak',
        'app.kubernetes.io/name': 'keycloak-headlamp-client'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'SkipDryRunOnMissingResource=true'], {
        limit: 10,
        backoff: {
          duration: '5s',
          factor: 2,
          maxDuration: '3m'
        }
      })
    }
  },
  {
    name: 'headlamp-keycloak-secrets',
    namespace: 'headlamp',
    chart: {
      type: 'HeadlampKeycloakSecretsChart'
    },
    dependencies: {
      keycloakHeadlampClient: {
        type: 'KeycloakHeadlampClientChart'
      }
    },
    argocd: {
      syncWave: '45',  // Before Headlamp deployment
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'headlamp',
        'app.kubernetes.io/name': 'headlamp-keycloak-secrets'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },
  {
    name: 'headlamp',
    namespace: 'headlamp',
    chart: {
      type: 'HeadlampChart',
      props: {
        enablePluginManager: true,
        plugins: [
          {
            name: 'external-secrets-operator',
            source: 'https://github.com/magohl/external-secrets-operator-headlamp-plugin/releases/download/0.1.0-beta7/external-secrets-operator-headlamp-plugin-0.1.0-beta7.tar.gz',
            version: '0.1.0-beta7'
          }
        ]
      }
    },
    dependencies: {
      headlampKeycloakSecrets: {
        type: 'HeadlampKeycloakSecretsChart'
      }
    },
    argocd: {
      syncWave: '60',  // After secrets, with other apps
      labels: {
        'app.kubernetes.io/component': 'dashboard',
        'app.kubernetes.io/part-of': 'headlamp',
        'app.kubernetes.io/name': 'headlamp'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },
  {
    name: 'kargo-secrets',
    namespace: 'kargo',
    chart: {
      type: 'KargoSecretsChart'
    },
    argocd: {
      syncWave: '-50',  // Deploy secrets before Kargo
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'kargo',
        'app.kubernetes.io/name': 'kargo-secrets'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },
  {
    name: 'kargo',
    namespace: 'kargo',
    chart: {
      type: 'KargoHelmChart'
    },
    dependencies: {
      kargoSecrets: {
        type: 'KargoSecretsChart'
      }
    },
    argocd: {
      syncWave: '70',  // Deploy after ArgoCD Helm app
      labels: {
        'app.kubernetes.io/component': 'continuous-delivery',
        'app.kubernetes.io/part-of': 'platform',
        'app.kubernetes.io/name': 'kargo',
        'app.kubernetes.io/instance': 'kargo',
        'app.kubernetes.io/version': '1.6.1'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true', 'Replace=true']
      },
      ignoreDifferences: [
        {
          group: 'cert-manager.io',
          kind: 'Certificate'
        },
        {
          group: 'cert-manager.io',
          kind: 'Issuer'
        },
        {
          group: 'batch',
          kind: 'Job',
          jsonPointers: [
            '/spec/podReplacementPolicy',
            '/status/terminating'
          ]
        }
      ]
    }
  },
  // Replaced with multi-env version - see bottom of file
  // {
  //   name: 'backstage',
  //   namespace: 'backstage',
  //   chart: {
  //     type: 'BackstageChart'
  //   },
  //   argocd: {
  //     syncWave: '20',
  //     annotations: {
  //       'kargo.akuity.io/authorized-stage': 'kargo-pipelines:backstage-dev'
  //     },
  //     labels: {
  //       'app.kubernetes.io/component': 'developer-portal',
  //       'app.kubernetes.io/part-of': 'platform',
  //       'app.kubernetes.io/name': 'backstage'
  //     },
  //     // Use default cnoe:// pattern like other applications
  //     syncPolicy: {
  //       automated: {
  //         prune: false,
  //         selfHeal: false
  //       },
  //       syncOptions: ['CreateNamespace=true']
  //     }
  //   }
  // },
  {
    name: 'kargo-pipelines-project',
    namespace: 'kargo-pipelines',
    chart: {
      type: 'KargoPipelinesProjectChart'
    },
    dependencies: {
      kargo: {
        type: 'KargoHelmChart'
      }
    },
    argocd: {
      syncWave: '75',  // After Kargo installation
      labels: {
        'app.kubernetes.io/component': 'project',
        'app.kubernetes.io/part-of': 'kargo-pipelines',
        'app.kubernetes.io/name': 'kargo-pipelines-project'
      },
      syncPolicy: {
        automated: {
          prune: false,           // Don't delete resources not in Git
          selfHeal: false         // Don't auto-revert manual changes
        },
        syncOptions: [
          'CreateNamespace=false',        // Namespace already exists with Kargo label
          'ApplyOutOfSyncOnly=true',      // Only sync resources that actually changed
          'RespectIgnoreDifferences=true', // Respect the ignore differences below
          'SkipDryRunOnMissingResource=true' // Skip dry-run for Kargo Project/ProjectConfig CRs
        ]
      },
      ignoreDifferences: [
        // Only ignore status fields that are managed by controllers
        { group: 'kargo.akuity.io', kind: 'Project', jsonPointers: ['/status'] },
        { group: 'kargo.akuity.io', kind: 'ProjectConfig', jsonPointers: ['/status'] }
      ]
    }
  },
  {
    name: 'kargo-pipelines-credentials',
    namespace: 'kargo-pipelines',
    chart: {
      type: 'KargoPipelinesCredentialsChart'
    },
    dependencies: {
      kargoPipelinesProject: {
        type: 'KargoPipelinesProjectChart'
      }
    },
    argocd: {
      syncWave: '76',  // After project creation
      labels: {
        'app.kubernetes.io/component': 'credentials',
        'app.kubernetes.io/part-of': 'kargo-pipelines',
        'app.kubernetes.io/name': 'kargo-pipelines-credentials'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'], {
        limit: 10,
        backoff: {
          duration: '5s',
          factor: 2,
          maxDuration: '3m'
        }
      })
    }
  },
  {
    name: 'kargo-ca-certificates',
    namespace: 'kargo',
    chart: {
      type: 'KargoCACertificatesChart'
    },
    argocd: {
      syncWave: '35',  // Before Kargo Helm chart (which is at 40)
      labels: {
        'app.kubernetes.io/component': 'certificates',
        'app.kubernetes.io/part-of': 'kargo',
        'app.kubernetes.io/name': 'kargo-ca-certificates'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=false']  // Namespace exists
      }
    }
  },
  {
    name: 'kargo-gitea-webhook-setup',
    namespace: 'kargo-pipelines',
    chart: {
      type: 'KargoGiteaWebhookSetupChart'
    },
    dependencies: {
      kargoPipelinesProject: {
        type: 'KargoPipelinesProjectChart'
      }
    },
    argocd: {
      syncWave: '85',  // After pipelines are created
      labels: {
        'app.kubernetes.io/component': 'webhook-setup',
        'app.kubernetes.io/part-of': 'kargo-pipelines',
        'app.kubernetes.io/name': 'kargo-gitea-webhook-setup',
        'app.kubernetes.io/managed-by': 'argocd'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'], {
        limit: 10,
        backoff: {
          duration: '5s',
          factor: 2,
          maxDuration: '3m'
        }
      })
    }
  },
  {
    name: 'dagger-infra',
    namespace: 'argo',
    chart: {
      type: 'DaggerInfraChart'
    },
    argocd: {
      syncWave: '-80',  // Deploy before Argo Workflows
      labels: {
        'app.kubernetes.io/component': 'rbac',
        'app.kubernetes.io/part-of': 'argo-workflows',
        'app.kubernetes.io/name': 'dagger-infra'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
    }
  },
  // Removed: Custom CoreDNS configuration is not needed
  // The *.localtest.me domain already resolves to 127.0.0.1 globally
  // Custom DNS rewriting was causing conflicts with IDPBuilder setup
  // Original configuration attempted to rewrite cnoe.localtest.me to ingress controller
  // {
  //   name: 'cluster-config',
  //   namespace: 'kube-system',
  //   chart: {
  //     type: 'ClusterConfigChart'
  //   },
  //   argocd: {
  //     syncWave: '-200',  // Very early, cluster configuration
  //     labels: {
  //       'app.kubernetes.io/component': 'cluster-config',
  //       'app.kubernetes.io/part-of': 'platform',
  //       'app.kubernetes.io/name': 'cluster-config'
  //     },
  //     syncPolicy: {
  //       automated: {
  //         prune: true,
  //         selfHeal: true
  //     },
  //       syncOptions: ['CreateNamespace=true']
  //     }
  //   }
  // },
  // Add more applications here as needed

  // Tailscale CRDs (Install CRDs before Tailscale operator)
  {
    name: 'tailscale-crds',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleCrdsChart'
    },
    argocd: {
      syncWave: '-120',  // Deploy CRDs very early, before tailscale-operator
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'tailscale',
        'app.kubernetes.io/name': 'tailscale-crds'
      },
      syncPolicy: {
        automated: {
          prune: false,  // Never auto-delete CRDs
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale Operator OAuth Secrets (from Azure Key Vault)
  // Prerequisites: Add TAILSCALE-OAUTH-CLIENT-ID and TAILSCALE-OAUTH-CLIENT-SECRET to Azure Key Vault
  {
    name: 'tailscale-operator-secrets',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleOperatorSecretsChart',
      props: {
        namespace: 'tailscale',
        syncWave: '-85'
      }
    },
    argocd: {
      syncWave: '-85',  // After bootstrap-secrets, before operator deployment
      labels: {
        'app.kubernetes.io/name': 'tailscale-operator-secrets',
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Tailscale Kubernetes Operator (manages Tailscale Ingress, ProxyGroups, etc.)
  // Centralizes certificate management to avoid Let's Encrypt rate limits
  {
    name: 'tailscale-operator',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleOperatorChart',
      props: {
        version: '1.82.0',
        namespace: 'tailscale',
        operatorHostname: 'kind-operator',
        defaultTags: ['tag:k8s-operator'],  // Must match OAuth client's permitted tags
        enableApiServerProxy: true,  // Enable kubectl access via kind-operator.tail286401.ts.net
        // OAuth identity impersonation: these tailnet identities get cluster-admin RBAC
        // Required for API Server Proxy "auth" mode (spec/103-tailscale-services)
        tailnetAdmins: ['vpittamp@github'],
        // Note: Uses default secret 'operator-oauth' created by tailscale-operator-secrets
      }
    },
    argocd: {
      syncWave: '-75',  // After operator secrets
      labels: {
        'app.kubernetes.io/name': 'tailscale-operator',
        'app.kubernetes.io/component': 'operator',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },

  // Tailscale Serve for Kubernetes API (kubectl access)
  // Replaces tailscale-api-proxy with Tailscale Services for stable URL
  // Access: https://k8s-api.<tailnet>.ts.net
  {
    name: 'k8s-api-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'K8sApiTailscaleServeChart',
      props: {
        serviceName: 'k8s-api',
        authKeySecretName: 'tailscale-auth-key',
        tailnetName: 'tail286401',
        createStaticTokenSecret: true,
        remoteAccessTokenSecretName: 'k8s-remote-access-token',
      }
    },
    argocd: {
      syncWave: '-60',
      labels: {
        'app.kubernetes.io/name': 'k8s-api-tailscale-serve',
        'app.kubernetes.io/component': 'api-proxy',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Tailscale Secrets (Auth key for Tailscale Services pods)
  {
    name: 'tailscale-secrets',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleSecretsChart',
      props: {
        namespace: 'tailscale',
        syncWave: '-70'  // Before tailscale pods that need the auth key
      }
    },
    argocd: {
      syncWave: '-70',  // After ClusterSecretStore, before tailscale pods
      labels: {
        'app.kubernetes.io/name': 'tailscale-secrets',
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Tailscale Subnet Router (exposes cluster pod and service networks to Tailscale)
  {
    name: 'tailscale-subnet-router',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleSubnetRouterChart',
      props: {
        namespace: 'tailscale',
        routes: ['10.244.0.0/16', '10.96.0.0/16'],  // Kind cluster pod and service CIDRs
        authKeySecretName: 'tailscale-auth-key',
        authKeySecretKey: 'authKey',
        // ServiceAccount is now created by the chart itself (no longer depends on operator)
      }
    },
    argocd: {
      syncWave: '-50',  // After operator and auth key are ready
      labels: {
        'app.kubernetes.io/name': 'tailscale-subnet-router',
        'app.kubernetes.io/component': 'subnet-router',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // =========================================================================
  // Tailscale Services - Stable URLs via --service flag (Constitution Principle V)
  // =========================================================================
  //
  // These serve charts replace the legacy TailscaleIngressChart pattern.
  // Benefits:
  // - Stable URLs (svc-<name>.<tailnet>.ts.net) that survive cluster recreation
  // - No hostname suffix drift (-1, -2, etc.)
  // - Persistent storage for certificates (avoids Let's Encrypt rate limits)
  // - ACL auto-approvers with tag:k8s-services
  //
  // Let's Encrypt Rate Limits (avoided via PVC):
  // - 5 certificates per domain per 168 hours (7 days)
  // - 10 new registrations per IP per 3 hours
  // - PVC persists /var/lib/tailscale across pod restarts

  // ArgoCD Tailscale Serve - Access: https://argocd2.tail286401.ts.net
  // Note: Using 'argocd2' to bypass Let's Encrypt rate limit on 'argocd'
  {
    name: 'argocd-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'argocd',  // Migrated from 'argocd2' - uses svc:argocd
        backendHost: 'argocd-server.argocd.svc.cluster.local',
        backendPort: 443,
        backendInsecure: true,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-60',  // After auth key secret
      labels: {
        'app.kubernetes.io/name': 'argocd-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Langfuse Tailscale Serve - Access: https://langfuse2.tail286401.ts.net
  // Note: Using 'langfuse2' to bypass Let's Encrypt rate limit on 'langfuse'
  {
    name: 'langfuse-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'langfuse2',
        backendHost: 'langfuse.observability.svc.cluster.local',
        backendPort: 3000,
        backendInsecure: false,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-55',  // After langfuse deployment
      labels: {
        'app.kubernetes.io/name': 'langfuse-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Gitea Tailscale Serve - Access: https://gitea2.tail286401.ts.net
  // Note: Using 'gitea2' to bypass Let's Encrypt rate limit on 'gitea'
  {
    name: 'gitea-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'gitea2',
        backendHost: 'my-gitea-http.gitea.svc.cluster.local',
        backendPort: 3000,
        backendInsecure: false,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/name': 'gitea-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // kagent Tailscale Serve - Access: https://kagent2.tail286401.ts.net
  // Note: Using 'kagent2' to bypass Let's Encrypt rate limit on 'kagent'
  {
    name: 'kagent-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'kagent2',
        backendHost: 'kagent-ui.kagent.svc.cluster.local',
        backendPort: 8080,
        backendInsecure: false,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/name': 'kagent-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Kargo Tailscale Serve - Access: https://kargo2.tail286401.ts.net
  // Note: Using 'kargo2' to bypass Let's Encrypt rate limit on 'kargo'
  {
    name: 'kargo-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'kargo2',
        backendHost: 'kargo-api.kargo.svc.cluster.local',
        backendPort: 80,
        backendInsecure: false,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/name': 'kargo-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Headlamp Tailscale Serve - Access: https://headlamp2.tail286401.ts.net
  // Note: Using 'headlamp2' to bypass Let's Encrypt rate limit on 'headlamp'
  {
    name: 'headlamp-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'headlamp2',
        backendHost: 'headlamp.headlamp.svc.cluster.local',
        backendPort: 80,
        backendInsecure: false,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/name': 'headlamp-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Keycloak Tailscale Serve - Access: https://keycloak2.tail286401.ts.net
  // Note: Using 'keycloak2' to bypass Let's Encrypt rate limit on 'keycloak'
  {
    name: 'keycloak-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'keycloak2',
        backendHost: 'keycloak.keycloak.svc.cluster.local',
        backendPort: 8080,
        backendInsecure: false,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/name': 'keycloak-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Gateway API CRDs (Required prerequisite for kgateway)
  {
    name: 'gateway-api-crds',
    namespace: 'default',
    chart: {
      type: 'GatewayApiCrdsChart',
      props: {
        version: 'v1.4.0'
      }
    },
    argocd: {
      syncWave: '-130',  // Deploy CRDs very early, before kgateway
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'kgateway',
        'app.kubernetes.io/name': 'gateway-api-crds'
      },
      syncPolicy: {
        automated: {
          prune: false,  // Never auto-delete CRDs
          selfHeal: true
        },
        syncOptions: ['ServerSideApply=true']
      }
    }
  },

  // kgateway CRDs (Install CRDs before kgateway platform)
  {
    name: 'kgateway-crds',
    namespace: 'kgateway-system',
    chart: {
      type: 'KgatewayCrdsChart',
      props: {
        version: 'v2.1.1'
      }
    },
    argocd: {
      syncWave: '-125',  // Deploy after Gateway API CRDs, before kgateway
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'kgateway',
        'app.kubernetes.io/name': 'kgateway-crds'
      },
      syncPolicy: {
        automated: {
          prune: false,  // Never auto-delete CRDs
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // kgateway with agentgateway enabled (MCP Server Gateway)
  {
    name: 'kgateway',
    namespace: 'kgateway-system',
    chart: {
      type: 'KgatewayChart',
      props: {
        version: 'v2.1.1',
        enableAgentGateway: true,
        enableAiExtension: true,
        replicas: 1
      }
    },
    argocd: {
      syncWave: '-120',  // Deploy after kgateway CRDs
      labels: {
        'app.kubernetes.io/component': 'platform',
        'app.kubernetes.io/part-of': 'kgateway',
        'app.kubernetes.io/name': 'kgateway'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // kagent CRDs (Install CRDs before kagent platform)
  {
    name: 'kagent-crds',
    namespace: 'kagent',
    chart: {
      type: 'KagentCrdsChart',
      props: {
        version: '0.7.4'
      }
    },
    argocd: {
      syncWave: '-115',  // Deploy after kgateway, before kagent
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'kagent',
        'app.kubernetes.io/name': 'kagent-crds'
      },
      syncPolicy: {
        automated: {
          prune: false,  // Never auto-delete CRDs
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // kagent AI Agent Framework
  {
    name: 'kagent',
    namespace: 'kagent',
    chart: {
      type: 'KagentChart',
      props: {
        version: '0.7.4',
        defaultProvider: 'openAI',
        enableKmcp: true,
        replicas: 1
      }
    },
    argocd: {
      syncWave: '-110',  // Deploy after kagent CRDs
      labels: {
        'app.kubernetes.io/component': 'platform',
        'app.kubernetes.io/part-of': 'kagent',
        'app.kubernetes.io/name': 'kagent'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['ServerSideApply=true']
      }
    }
  },

  // kagent LLM Provider Secrets (External Secrets from Azure Key Vault)
  {
    name: 'kagent-secrets',
    namespace: 'kagent',
    chart: {
      type: 'KagentSecretsChart',
      props: {
        namespace: 'kagent',
        secretName: 'kagent-llm-providers',
        clusterSecretStoreName: 'azure-keyvault-store',
        refreshInterval: '1h'
      }
    },
    argocd: {
      syncWave: '-112',  // Deploy after kagent-crds (-115), before kagent (-110) which needs the secrets
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'kagent',
        'app.kubernetes.io/name': 'kagent-secrets'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(['CreateNamespace=false']),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Nix Cache Namespace
  {
    name: 'nix-cache-namespace',
    namespace: 'nix-cache',
    chart: {
      type: 'NixCacheNamespaceChart',
      props: {
        namespaceName: 'nix-cache'
      }
    },
    argocd: {
      syncWave: '-110',  // Deploy namespace before MinIO
      labels: {
        'app.kubernetes.io/name': 'nix-cache',
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'nix-cache'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
    }
  },

  // MinIO Object Storage (S3-compatible storage for Nix binary cache)
  {
    name: 'minio',
    namespace: 'nix-cache',
    chart: {
      type: 'MinioChart',
      props: {
        storageSize: '100Gi',
        rootUser: 'admin'
      }
    },
    argocd: {
      syncWave: '-100',  // Deploy before Attic
      labels: {
        'app.kubernetes.io/name': 'minio',
        'app.kubernetes.io/component': 'object-storage',
        'app.kubernetes.io/part-of': 'nix-cache'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
    }
  },

  // Attic Nix Binary Cache Server
  {
    name: 'attic',
    namespace: 'nix-cache',
    chart: {
      type: 'AtticChart',
      props: {
        minioEndpoint: 'http://minio.nix-cache.svc.cluster.local:9000',
        bucketName: 'attic-cache'
      }
    },
    argocd: {
      syncWave: '-90',  // Deploy after MinIO
      labels: {
        'app.kubernetes.io/name': 'attic',
        'app.kubernetes.io/component': 'nix-cache-server',
        'app.kubernetes.io/part-of': 'nix-cache'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // =========================================================================
  // Observability Stack - Jaeger + Langfuse
  // =========================================================================

  // Observability Namespace
  {
    name: 'observability-namespace',
    namespace: 'observability',
    chart: {
      type: 'ObservabilityNamespaceChart',
      props: {
        namespaceName: 'observability'
      }
    },
    argocd: {
      syncWave: '-70',
      labels: {
        'app.kubernetes.io/name': 'observability-namespace',
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'observability'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
    }
  },

  // Observability Secrets (from Azure Key Vault)
  {
    name: 'observability-secrets',
    namespace: 'observability',
    chart: {
      type: 'ObservabilitySecretsChart',
      props: {
        namespace: 'observability',
        clusterSecretStoreName: 'azure-keyvault-store',
        refreshInterval: '1h'
      }
    },
    argocd: {
      syncWave: '-75',
      labels: {
        'app.kubernetes.io/name': 'observability-secrets',
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'observability'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(['CreateNamespace=false']),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Jaeger Distributed Tracing
  {
    name: 'jaeger',
    namespace: 'observability',
    chart: {
      type: 'JaegerChart',
      props: {
        namespace: 'observability',
        imageVersion: '1.66.0', // Latest 1.x version (2.x doesn't exist yet as tagged release)
        storageSize: '10Gi',
        spanStorageTtl: '168h',
        ingressHost: 'jaeger.cnoe.localtest.me'
      }
    },
    argocd: {
      syncWave: '-65',
      labels: {
        'app.kubernetes.io/name': 'jaeger',
        'app.kubernetes.io/component': 'tracing',
        'app.kubernetes.io/part-of': 'observability'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // Langfuse PostgreSQL Database
  {
    name: 'langfuse-postgres',
    namespace: 'observability',
    chart: {
      type: 'LangfusePostgresChart',
      props: {
        namespace: 'observability',
        image: 'postgres:16-alpine',
        storageSize: '20Gi',
        databaseName: 'langfuse',
        credentialsSecretName: 'langfuse-postgres-credentials'
      }
    },
    argocd: {
      syncWave: '-75',
      labels: {
        'app.kubernetes.io/name': 'langfuse-postgres',
        'app.kubernetes.io/component': 'database',
        'app.kubernetes.io/part-of': 'observability'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // Langfuse ClickHouse (v3 requirement)
  {
    name: 'langfuse-clickhouse',
    namespace: 'observability',
    chart: {
      type: 'LangfuseClickhouseChart',
      props: {
        namespace: 'observability',
        imageVersion: '24.3',
        storageSize: '10Gi'
      }
    },
    argocd: {
      syncWave: '-70',
      labels: {
        'app.kubernetes.io/name': 'langfuse-clickhouse',
        'app.kubernetes.io/component': 'database',
        'app.kubernetes.io/part-of': 'observability'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // Langfuse Redis (v3 requirement)
  {
    name: 'langfuse-redis',
    namespace: 'observability',
    chart: {
      type: 'LangfuseRedisChart',
      props: {
        namespace: 'observability',
        imageVersion: '7-alpine',
        enablePersistence: false
      }
    },
    argocd: {
      syncWave: '-70',
      labels: {
        'app.kubernetes.io/name': 'langfuse-redis',
        'app.kubernetes.io/component': 'cache',
        'app.kubernetes.io/part-of': 'observability'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // Langfuse MinIO (v3 requirement for blob storage)
  {
    name: 'langfuse-minio',
    namespace: 'observability',
    chart: {
      type: 'LangfuseMinioChart',
      props: {
        namespace: 'observability',
        storageSize: '10Gi',
        bucketName: 'langfuse'
      }
    },
    argocd: {
      syncWave: '-70',
      labels: {
        'app.kubernetes.io/name': 'langfuse-minio',
        'app.kubernetes.io/component': 'blob-storage',
        'app.kubernetes.io/part-of': 'observability'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // Langfuse LLM Observability (v3 with full infrastructure)
  // Access via Tailscale: https://langfuse-2.tail286401.ts.net/
  {
    name: 'langfuse',
    namespace: 'observability',
    chart: {
      type: 'LangfuseChart',
      props: {
        namespace: 'observability',
        imageVersion: '3',
        postgresHost: 'langfuse-postgres',
        postgresPort: 5432,
        databaseName: 'langfuse',
        clickhouseHost: 'langfuse-clickhouse',
        clickhouseUser: 'default',
        clickhousePassword: 'clickhouse_langfuse_password',
        redisHost: 'langfuse-redis',
        minioHost: 'langfuse-minio',
        minioUser: 'minioadmin',
        minioPassword: 'minio_langfuse_password',
        credentialsSecretName: 'langfuse-postgres-credentials',
        clickhouseCredentialsSecretName: 'langfuse-clickhouse-credentials',
        minioCredentialsSecretName: 'langfuse-minio-credentials',
        authSecretName: 'langfuse-auth',
        ingressHost: 'langfuse.cnoe.localtest.me',
        // Use Tailscale Services URL for remote access (NextAuth requires exact URL match)
        // Format: <name>.<tailnet>.ts.net - stable URL that survives cluster recreation
        // Note: Using 'langfuse2' to bypass Let's Encrypt rate limit on 'langfuse'
        nextAuthUrl: 'https://langfuse2.tail286401.ts.net'
      }
    },
    argocd: {
      syncWave: '-60',
      labels: {
        'app.kubernetes.io/name': 'langfuse',
        'app.kubernetes.io/component': 'llm-observability',
        'app.kubernetes.io/part-of': 'observability'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // Dapr Tracing Configuration (for SpecKit agents)
  {
    name: 'dapr-tracing-config',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprTracingConfigChart',
      props: {
        namespace: 'dapr-agents',
        configName: 'speckit-tracing',
        samplingRate: '1',
        zipkinEndpoint: 'http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans'
      }
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/name': 'dapr-tracing-config',
        'app.kubernetes.io/component': 'tracing',
        'app.kubernetes.io/part-of': 'speckit-agents'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // =========================================================================
  // Dapr Agents - SpecKit Multi-Agent Workflow System
  // =========================================================================

  // Dapr CRDs - Must be installed before Dapr runtime
  // These CRDs are required for Dapr components, configurations, subscriptions, etc.
  {
    name: 'dapr-crds',
    namespace: 'default',  // CRDs are cluster-scoped
    chart: {
      type: 'DaprCrdsChart',
      props: {
        daprVersion: 'v1.16.3'
      }
    },
    argocd: {
      syncWave: '-200',  // Deploy CRDs very early, before dapr-runtime
      labels: {
        'app.kubernetes.io/name': 'dapr-crds',
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'dapr-agents'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['ServerSideApply=true', 'Replace=true']
      }
    }
  },

  // Dapr Runtime (Control Plane)
  {
    name: 'dapr-runtime',
    namespace: 'dapr-system',
    chart: {
      type: 'DaprRuntimeChart',
      props: {
        version: '1.16',
        enableHA: false,
        enableDashboard: true,
        logLevel: 'info'
      }
    },
    argocd: {
      syncWave: '-120',  // Deploy Dapr control plane early
      labels: {
        'app.kubernetes.io/name': 'dapr-runtime',
        'app.kubernetes.io/component': 'control-plane',
        'app.kubernetes.io/part-of': 'dapr-agents'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Dapr Agents Redis (State and Pub/Sub backend)
  {
    name: 'dapr-agents-redis',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprAgentsRedisChart',
      props: {
        namespace: 'dapr-agents',
        replicas: 1,
        enablePersistence: false  // For dev environment
      }
    },
    argocd: {
      syncWave: '-100',  // Deploy Redis before Dapr components
      labels: {
        'app.kubernetes.io/name': 'dapr-agents-redis',
        'app.kubernetes.io/component': 'state-store',
        'app.kubernetes.io/part-of': 'dapr-agents'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
    }
  },

  // Dapr Agents Secrets (LLM API keys from Azure Key Vault)
  {
    name: 'dapr-agents-secrets',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprAgentsSecretsChart',
      props: {
        namespace: 'dapr-agents',
        secretName: 'dapr-agents-llm-providers',
        clusterSecretStoreName: 'azure-keyvault-store',
        refreshInterval: '1h'
      }
    },
    argocd: {
      syncWave: '-95',  // Deploy secrets before Dapr components need them
      labels: {
        'app.kubernetes.io/name': 'dapr-agents-secrets',
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'dapr-agents'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Dapr Components (State stores, Pub/Sub, Conversation)
  {
    name: 'dapr-components',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprComponentsChart',
      props: {
        namespace: 'dapr-agents',
        redisHost: 'redis-service.dapr-agents.svc.cluster.local:6379',
        llmSecretName: 'dapr-agents-llm-providers',
        anthropicModel: 'claude-opus-4-5-20251101',
        cacheTTL: '10m'
      }
    },
    argocd: {
      syncWave: '-90',  // Deploy Dapr components after Redis and secrets
      labels: {
        'app.kubernetes.io/name': 'dapr-components',
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'dapr-agents'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // SpecKit Agents RBAC (ServiceAccount, Role, RoleBinding)
  {
    name: 'speckit-agents-rbac',
    namespace: 'dapr-agents',
    chart: {
      type: 'SpecKitAgentsRbacChart',
      props: {
        namespace: 'dapr-agents'
      }
    },
    argocd: {
      syncWave: '-80',  // Deploy RBAC before agents
      labels: {
        'app.kubernetes.io/name': 'speckit-agents-rbac',
        'app.kubernetes.io/component': 'rbac',
        'app.kubernetes.io/part-of': 'speckit'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // SpecKit Agents (Orchestrator, Specifier, Planner, TaskGenerator, Implementer)
  {
    name: 'speckit-agents',
    namespace: 'dapr-agents',
    chart: {
      type: 'SpecKitAgentsChart',
      props: {
        namespace: 'dapr-agents',
        agentImage: 'vpittamp/speckit-agents',  // Local image loaded into kind
        imageTag: 'claude-sdk-v9',  // Fixed: all directory creation issues
        teamName: 'speckit',
        pubsubName: 'messagepubsub',
        workflowStateStore: 'workflowstatestore',
        registryStateStore: 'agentregistrystore',
        memoryStore: 'memorystore',
        conversationComponent: 'anthropic',
        llmSecretName: 'dapr-agents-llm-providers'
      }
    },
    argocd: {
      syncWave: '50',  // Deploy agents late to ensure Dapr sidecar injector webhook is ready
      labels: {
        'app.kubernetes.io/name': 'speckit-agents',
        'app.kubernetes.io/component': 'agents',
        'app.kubernetes.io/part-of': 'speckit'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  }
];
