import { ApplicationConfig } from '../lib/idpbuilder-types';
import { automatedSyncWithOptions } from '../lib/argocd-sync-builders';

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

  // KubeVirt Infrastructure (Virtual Machine Platform)
  // KubeVirt Operator - deploys CRDs and operator
  {
    name: 'kubevirt-operator',
    namespace: 'kubevirt',
    chart: {
      type: 'KubeVirtOperatorChart',
      props: {
        version: 'v1.3.1'
      }
    },
    argocd: {
      syncWave: '-110',  // Deploy very early with CRDs
      labels: {
        'app.kubernetes.io/name': 'kubevirt-operator',
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'platform'
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

  // KubeVirt CR - creates KubeVirt instance with software emulation
  {
    name: 'kubevirt-cr',
    namespace: 'kubevirt',
    chart: {
      type: 'KubeVirtCRChart',
      props: {
        useEmulation: true  // Required for Kind cluster (no KVM access)
      }
    },
    argocd: {
      syncWave: '-90',  // After operator deploys CRDs
      labels: {
        'app.kubernetes.io/name': 'kubevirt-cr',
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'platform'
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

  // CDI (Containerized Data Importer) for VM Disk Images
  // CDI Operator - deploys CRDs and operator
  {
    name: 'cdi-operator',
    namespace: 'cdi',
    chart: {
      type: 'CDIOperatorChart',
      props: {
        version: 'v1.59.0'
      }
    },
    argocd: {
      syncWave: '-110',  // Deploy alongside KubeVirt operator
      labels: {
        'app.kubernetes.io/name': 'cdi-operator',
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'platform'
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

  // CDI CR - creates CDI instance
  {
    name: 'cdi-cr',
    namespace: 'cdi',
    chart: {
      type: 'CDICRChart'
    },
    argocd: {
      syncWave: '-90',  // After operator deploys CRDs
      labels: {
        'app.kubernetes.io/name': 'cdi-cr',
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'platform'
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

  // NixOS Image Server (HTTP server for qcow2 images from Docker Hub)
  {
    name: 'nixos-image-server',
    namespace: 'default',
    chart: {
      type: 'NixOsImageServerChart',
      props: {
        image: 'vpittamp23/nixos-kubevirt-desktop:v1.0.0-x11'
      }
    },
    argocd: {
      syncWave: '-50',  // Before DataVolumes
      labels: {
        'app.kubernetes.io/name': 'nixos-image-server',
        'app.kubernetes.io/component': 'image-server',
        'app.kubernetes.io/part-of': 'kubevirt'
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

  // NixOS DataVolume (Import NixOS image into PVC)
  {
    name: 'nixos-dev-datavolume',
    namespace: 'default',
    chart: {
      type: 'NixOsDataVolumeChart',
      props: {
        dataVolumeName: 'nixos-dev-datavolume',
        imageUrl: 'http://nixos-image-server.default.svc.cluster.local/nixos.qcow2',
        storageSize: '50Gi'  // Need 50Gi for full KDE Plasma 6 desktop (~25.5 GB system + overhead)
      }
    },
    argocd: {
      syncWave: '0',  // After image server
      labels: {
        'app.kubernetes.io/name': 'nixos-dev-datavolume',
        'app.kubernetes.io/component': 'storage',
        'app.kubernetes.io/part-of': 'kubevirt'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // Tailscale VM Secrets (Auth key for VM Tailscale authentication)
  {
    name: 'tailscale-vm-secrets',
    namespace: 'default',
    chart: {
      type: 'TailscaleVmSecretsChart',
      props: {
        namespace: 'default',
        syncWave: '5'  // Before VM creation
      }
    },
    argocd: {
      syncWave: '5',  // Before VM
      labels: {
        'app.kubernetes.io/name': 'tailscale-vm-secrets',
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'kubevirt'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
    }
  },

  // NixOS Virtual Machine
  {
    name: 'nixos-dev-vm',
    namespace: 'default',
    chart: {
      type: 'NixOsVmChart',
      props: {
        vmName: 'nixos-dev-vm',
        dataVolumeName: 'nixos-dev-datavolume',
        cpuCores: 8,  // Increased to 8 for maximum performance
        memory: '32Gi',  // Increased to 32Gi for smooth desktop experience with full NixOS config
        enableTailscale: true,  // Enable Tailscale LoadBalancer for direct IP access
        tailscaleHostname: 'nixos-dev-vm'  // Tailscale hostname (without -rdp suffix)
      }
    },
    argocd: {
      syncWave: '10',  // After DataVolume
      labels: {
        'app.kubernetes.io/name': 'nixos-dev-vm',
        'app.kubernetes.io/component': 'virtual-machine',
        'app.kubernetes.io/part-of': 'kubevirt'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
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
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
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
  //           duration: '10s',
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
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'SkipDryRunOnMissingResource=true'])
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
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
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
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
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
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
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
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=true']
      }
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

  // Tailscale Operator - Remote Kubernetes Cluster Access
  // Enables LoadBalancer service exposure via Tailscale network
  // TODO: Re-enable when tailscale.com CRD imports are generated
  // {
  //   name: 'tailscale-operator',
  //   namespace: 'tailscale',
  //   chart: {
  //     type: 'TailscaleOperatorChart',
  //     props: {
  //       environmentName: process.env.ENVIRONMENT_NAME as 'dev' | 'staging' | 'production' || 'dev',
  //       clusterName: process.env.CLUSTER_NAME || 'kind',
  //       oauthSecretName: 'tailscale-oauth',
  //       enableHA: false,  // Disable ProxyGroup in dev (conflicts with APISERVER_PROXY=true)
  //       proxyReplicas: 2,
  //       impersonationGrants: [
  //         {
  //           tailscaleGroup: 'group:admins',
  //           kubernetesGroups: ['system:masters'],
  //           description: 'Full cluster admin access for Tailscale admin group'
  //         },
  //         {
  //           tailscaleGroup: 'group:developers',
  //           kubernetesGroups: ['developers'],
  //           description: 'Developer namespace access via Kubernetes RBAC'
  //         }
  //       ]
  //     }
  //   },
  //   dependencies: {
  //     tailscaleCrds: {
  //       type: 'TailscaleCrdsChart'
  //     }
  //   },
  //   argocd: {
  //     syncWave: '-90',  // Deploy after CRDs
  //     labels: {
  //       'app.kubernetes.io/name': 'tailscale-operator',
  //       'app.kubernetes.io/component': 'network-proxy'
  //     },
  //     syncPolicy: {
  //       automated: { prune: true, selfHeal: true },
  //       syncOptions: ['SkipDryRunOnMissingResource=true']
  //     }
  //   }
  // },

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
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
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

  // Tailscale Serve endpoint for ArgoCD UI (userspace, independent of operator proxy)
  // Uses Tailscale Services for stable URL: https://svc:argocd.<tailnet>.ts.net
  {
    name: 'argocd-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'ArgoCdTailscaleServeChart',
      props: {
        serviceName: 'argocd',
        backendHost: 'argocd-server.argocd.svc.cluster.local',
        backendPort: 443,
        backendInsecure: true, // ArgoCD uses self-signed certs
        // Set legacyHostnameMode: true to revert to hostname-based access
        // legacyHostnameMode: true,
        // legacyHostname: 'argocd-ui-serve',
      }
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/name': 'argocd-tailscale-serve',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale Serve endpoint for Langfuse (userspace, independent of operator proxy)
  // Uses Tailscale Services for stable URL: https://svc:langfuse.<tailnet>.ts.net
  {
    name: 'langfuse-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'LangfuseTailscaleServeChart',
      props: {
        serviceName: 'langfuse',
        backendHost: 'langfuse.observability.svc.cluster.local',
        backendPort: 3000,
        backendScheme: 'http', // Langfuse uses HTTP internally
        // Set legacyHostnameMode: true to revert to hostname-based access
        // legacyHostnameMode: true,
        // legacyHostname: 'langfuse',
      }
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/name': 'langfuse-tailscale-serve',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale Serve for Gitea (Git server)
  // Uses Tailscale Services for stable URL: https://gitea.<tailnet>.ts.net
  {
    name: 'gitea-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'gitea',
        backendHost: 'my-gitea-http.gitea.svc.cluster.local',
        backendPort: 3000,
        backendScheme: 'http',
        deploymentName: 'gitea-tailscale-serve',
        partOf: 'gitea'
      }
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/name': 'gitea-tailscale-serve',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale Serve for Keycloak (Identity provider)
  // Uses Tailscale Services for stable URL: https://keycloak.<tailnet>.ts.net
  {
    name: 'keycloak-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'keycloak',
        backendHost: 'keycloak.keycloak.svc.cluster.local',
        backendPort: 8080,
        backendScheme: 'http',
        deploymentName: 'keycloak-tailscale-serve',
        partOf: 'keycloak'
      }
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/name': 'keycloak-tailscale-serve',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale Serve for Headlamp (Kubernetes dashboard)
  // Uses Tailscale Services for stable URL: https://headlamp.<tailnet>.ts.net
  {
    name: 'headlamp-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'headlamp',
        backendHost: 'headlamp.headlamp.svc.cluster.local',
        backendPort: 80,
        backendScheme: 'http',
        deploymentName: 'headlamp-tailscale-serve',
        partOf: 'headlamp'
      }
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/name': 'headlamp-tailscale-serve',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale Serve for Kargo (GitOps promotion controller)
  // Uses Tailscale Services for stable URL: https://kargo.<tailnet>.ts.net
  {
    name: 'kargo-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'kargo',
        backendHost: 'kargo-api.kargo.svc.cluster.local',
        backendPort: 443,
        backendInsecure: true, // Kargo uses self-signed certs - this will use https+insecure://
        deploymentName: 'kargo-tailscale-serve',
        partOf: 'kargo'
      }
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/name': 'kargo-tailscale-serve',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale Serve for Kagent (AI agent dashboard)
  // Uses Tailscale Services for stable URL: https://kagent.<tailnet>.ts.net
  {
    name: 'kagent-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'kagent',
        backendHost: 'kagent-dashboard.kagent.svc.cluster.local',
        backendPort: 8080,
        backendScheme: 'http',
        deploymentName: 'kagent-tailscale-serve',
        partOf: 'kagent'
      }
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/name': 'kagent-tailscale-serve',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailscale exposure for all ingress hosts via ingress-nginx
  // Sync wave 50: Delayed to allow Tailscale device cleanup grace period (120s) to complete
  // during cluster recreation. Early sync wave (-35) caused hostname conflicts (-3 suffix).
  {
    name: 'ingress-tailscale-publish',
    namespace: 'ingress-nginx',
    chart: { type: 'IngressTailscalePublishChart' },
    argocd: {
      syncWave: '50',
      labels: {
        'app.kubernetes.io/name': 'ingress-tailscale-publish',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
      }
    }
  },

  // Tailnet host aliases to match ingress hosts so SNI/Host route correctly
  {
    name: 'tailnet-ingress-alias',
    namespace: 'ingress-nginx',
    chart: { type: 'TailnetIngressAliasChart' },
    argocd: {
      syncWave: '51',
      labels: {
        'app.kubernetes.io/name': 'tailnet-ingress-alias',
        'app.kubernetes.io/component': 'network',
        'app.kubernetes.io/part-of': 'tailscale'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true']
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
      syncWave: '-70',  // Deploy after kagent namespace exists, before agents
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'kagent',
        'app.kubernetes.io/name': 'kagent-secrets'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['CreateNamespace=false']  // Namespace created by kagent-crds
      }
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
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
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
        // Format: svc:<name>.<tailnet>.ts.net - stable URL that survives cluster recreation
        nextAuthUrl: 'https://svc-langfuse.tail286401.ts.net'
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
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        }
      }
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
        agentImage: 'docker.io/vpittamp23/speckit-agents',  // Public image on Docker Hub
        imageTag: 'langfuse-sessions-v3',  // Fixed session ID extraction from call_llm payload
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
      syncWave: '-60',  // Deploy agents after all infrastructure is ready
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
