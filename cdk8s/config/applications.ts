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
        image: 'vpittamp23/nixos-kubevirt-desktop:v1.1.0-tailscale'
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

  // RustDesk VM Secrets (Password for RustDesk remote desktop authentication)
  // DEPRECATED: Use nixos-vm-cloudinit-secrets instead for production
  // This chart is kept for backward compatibility with inline cloud-init approach
  {
    name: 'rustdesk-secrets',
    namespace: 'default',
    chart: {
      type: 'RustDeskSecretsChart',
      props: {
        namespace: 'default',
        syncWave: '-70'  // Before VM creation (early in deployment)
      }
    },
    argocd: {
      syncWave: '-70',  // Before VM deployment (wave 0)
      labels: {
        'app.kubernetes.io/name': 'rustdesk-secrets',
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

  // NixOS VM Cloud-Init Secrets (Production approach: generates cloud-init with secrets from Azure Key Vault)
  {
    name: 'nixos-vm-cloudinit-secrets',
    namespace: 'default',
    chart: {
      type: 'NixOsVmCloudInitSecretsChart',
      props: {
        namespace: 'default',
        vmName: 'nixos-dev-vm',
        username: 'vpittamp',
        sshKeys: ['ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHmXFP33EvyB3vZQktX+FvxdzfUVclE6bk0dd3nMAq84 hetzner-nixos'],
        consolePassword: 'nixos123',
        enableTailscale: true,
        enableRustDesk: true,
        syncWave: '5'  // Before VM creation (wave 10)
      }
    },
    argocd: {
      syncWave: '5',  // After workload identity, before VM
      labels: {
        'app.kubernetes.io/name': 'nixos-vm-cloudinit-secrets',
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
        tailscaleHostname: 'nixos-dev-vm',  // Tailscale hostname (without -rdp suffix)
        useExternalSecretsCloudInit: true  // Use production-ready ExternalSecret for cloud-init
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
      syncWave: '-100',
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
  {
    name: 'tailscale-operator',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleOperatorChart',
      props: {
        environmentName: process.env.ENVIRONMENT_NAME as 'dev' | 'staging' | 'production' || 'dev',
        clusterName: process.env.CLUSTER_NAME || 'kind',
        oauthSecretName: 'tailscale-oauth',
        enableHA: true,  // Enable ProxyGroup for API server access
        proxyReplicas: 2,
        impersonationGrants: [
          {
            tailscaleGroup: 'group:admins',
            kubernetesGroups: ['system:masters'],
            description: 'Full cluster admin access for Tailscale admin group'
          },
          {
            tailscaleGroup: 'group:developers',
            kubernetesGroups: ['developers'],
            description: 'Developer namespace access via Kubernetes RBAC'
          }
        ]
      }
    },
    dependencies: {
      tailscaleCrds: {
        type: 'TailscaleCrdsChart'
      }
    },
    argocd: {
      syncWave: '-90',  // Deploy after CRDs
      labels: {
        'app.kubernetes.io/name': 'tailscale-operator',
        'app.kubernetes.io/component': 'network-proxy'
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true
        },
        syncOptions: ['SkipDryRunOnMissingResource=true']  // Skip dry-run for ProxyGroup CR until CRD is installed
      }
    }
  },

  // Tailscale API Proxy (sidecar approach)
  {
    name: 'tailscale-api-proxy',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleApiProxyChart',
      props: {
        clusterName: process.env.CLUSTER_NAME || 'kind',
        authKeySecretName: 'tailscale-auth-key',
        tailscaleImage: 'tailscale/tailscale:latest',
        kubectlImage: 'bitnami/kubectl:latest'
      }
    },
    argocd: {
      syncWave: '-60',
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
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
        serviceAccountName: 'operator'
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

  // kagent CRDs (Install CRDs before kagent platform)
  {
    name: 'kagent-crds',
    namespace: 'kagent',
    chart: {
      type: 'KagentCrdsChart'
    },
    argocd: {
      syncWave: '-120',  // Deploy CRDs very early, before kagent
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

  // TEMPORARILY DISABLED: kagent applications have TypeScript errors
  // TODO: Re-enable after fixing kagent import errors

  // // kagent Platform (AI Agent Infrastructure)
  // {
  //   name: 'kagent',
  //   namespace: 'kagent',
  //   chart: {
  //     type: 'KagentChart'
  //   },
  //   dependencies: {
  //     kagentCrds: {
  //       type: 'KagentCrdsChart'
  //     }
  //   },
  //   argocd: {
  //     syncWave: '-110',  // Deploy after CRDs
  //     labels: {
  //       'app.kubernetes.io/component': 'platform',
  //       'app.kubernetes.io/part-of': 'kagent',
  //       'app.kubernetes.io/name': 'kagent'
  //     },
  //     syncPolicy: {
  //       automated: {
  //         prune: true,
  //         selfHeal: true
  //       },
  //       syncOptions: ['SkipDryRunOnMissingResource=true']  // Skip dry-run for RemoteMCPServer CR until CRD is installed
  //     }
  //   }
  // },
  //
  // // kmcp Controller (MCP Server Manager)
  // {
  //   name: 'kmcp',
  //   namespace: 'kagent',
  //   chart: {
  //     type: 'KmcpChart'
  //   },
  //   dependencies: {
  //     kagentCrds: {
  //       type: 'KagentCrdsChart'
  //     }
  //   },
  //   argocd: {
  //     syncWave: '-110',  // Deploy alongside kagent, after CRDs
  //     labels: {
  //       'app.kubernetes.io/component': 'platform',
  //       'app.kubernetes.io/part-of': 'kagent',
  //       'app.kubernetes.io/name': 'kmcp'
  //     },
  //     syncPolicy: {
  //       automated: {
  //         prune: true,
  //         selfHeal: true
  //       },
  //       syncOptions: ['SkipDryRunOnMissingResource=true']  // Skip dry-run for MCPServer CRs until CRD is installed
  //     }
  //   }
  // },
  //
  // // kagent Secrets (LLM Provider API Keys)
  // {
  //   name: 'kagent-secrets',
  //   namespace: 'kagent',
  //   chart: {
  //     type: 'KagentSecretsChart'
  //   },
  //   argocd: {
  //     syncWave: '-70',  // After workload identity, before agents
  //     labels: {
  //       'app.kubernetes.io/component': 'secrets',
  //       'app.kubernetes.io/part-of': 'kagent',
  //       'app.kubernetes.io/name': 'kagent-secrets'
  //     },
  //     syncPolicy: {
  //       automated: {
  //         prune: true,
  //         selfHeal: true
  //       }
  //     }
  //   }
  // },
  //
  // // kagent Example Agents
  // {
  //   name: 'kagent-agents',
  //   namespace: 'kagent',
  //   chart: {
  //     type: 'KagentExampleAgentsChart'
  //   },
  //   dependencies: {
  //     kagentSecrets: {
  //       type: 'KagentSecretsChart'
  //     }
  //   },
  //   argocd: {
  //     syncWave: '50',  // After platform is ready
  //     labels: {
  //       'app.kubernetes.io/component': 'agents',
  //       'app.kubernetes.io/part-of': 'kagent',
  //       'app.kubernetes.io/name': 'kagent-agents'
  //     },
  //     syncPolicy: {
  //       automated: {
  //         prune: true,
  //         selfHeal: true
  //       },
  //       syncOptions: ['SkipDryRunOnMissingResource=true']  // Skip dry-run for Agent/ModelConfig/MCPServer CRs
  //     },
  //     // Ignore status and spec fields updated by controllers
  //     // The kagent controller adds default values to Agent specs (a2aConfig, modelConfig, systemMessage, tools)
  //     ignoreDifferences: [
  //       { group: 'kagent.dev', kind: 'Agent', jsonPointers: ['/status', '/spec'] },
  //       { group: 'kagent.dev', kind: 'ModelConfig', jsonPointers: ['/status'] },
  //       { group: 'kagent.dev', kind: 'MCPServer', jsonPointers: ['/status'] }
  //     ]
  //   }
  // },

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
  }
];
