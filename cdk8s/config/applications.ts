import { ApplicationConfig } from '../lib/idpbuilder-types';
import {
  automatedSyncWithOptions,
  externalSecretsAppSyncPolicy,
  EXTERNAL_SECRET_IGNORE_DIFFERENCES
} from '../lib/argocd-sync-builders';

/**
 * Cluster host detection for multi-host deployments.
 * When CLUSTER_HOST is set, Tailscale service names include the hostname
 * to prevent collisions between clusters on different hosts.
 *
 * Examples:
 * - CLUSTER_HOST=thinkpad -> svc:argocd-thinkpad
 * - CLUSTER_HOST=ryzen -> svc:argocd-ryzen
 * - CLUSTER_HOST not set -> svc:argocd (backward compatible)
 */
const clusterHost = process.env.CLUSTER_HOST || '';
const hostSuffix = clusterHost ? `-${clusterHost}` : '';

/**
 * Generate host-aware service name for Tailscale Services.
 * @param baseName - Base service name (e.g., 'argocd')
 * @returns Host-aware service name (e.g., 'argocd-thinkpad')
 */
function getTailscaleServiceName(baseName: string): string {
  return `${baseName}${hostSuffix}`;
}

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

  // =========================================================================
  // Talos Infrastructure - TLS Certificate Management
  // These apps are required for Let's Encrypt TLS certificates on Talos cluster
  // Dependency chain: eso-workload-identity → cluster-secret-store → cert-manager-secrets → cloudflare-issuer
  // =========================================================================

  // ESO Workload Identity Patch - Azure AD federation for external-secrets ServiceAccount
  // Required by: cluster-secret-store (ClusterSecretStore needs annotated ServiceAccount)
  {
    name: 'eso-workload-identity',
    namespace: 'external-secrets',
    clusterType: 'talos',  // Only needed on Talos for Azure Workload Identity
    chart: {
      type: 'WorkloadIdentityPatchChart',
      props: {
        clientId: process.env.AZURE_CLIENT_ID || '',
        tenantId: process.env.AZURE_TENANT_ID || '',
        serviceAccountName: 'external-secrets',
        serviceAccountNamespace: 'external-secrets'
      }
    },
    argocd: {
      syncWave: '-90',  // Before cluster-secret-store (-88)
      labels: {
        'app.kubernetes.io/component': 'workload-identity',
        'app.kubernetes.io/part-of': 'external-secrets',
        'app.kubernetes.io/name': 'eso-workload-identity'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])  // Merge with existing SA
    }
  },

  // ClusterSecretStore - Azure Key Vault access (cluster-scoped)
  // Required by: cert-manager-secrets, keycloak-secrets, backstage-secrets
  {
    name: 'cluster-secret-store',
    namespace: 'external-secrets',  // ESO namespace
    clusterType: 'talos',  // Only needed on Talos (KIND uses localtest.me without TLS)
    chart: {
      type: 'ClusterSecretStoreChart',
      props: {
        storeName: 'azure-keyvault-store',
        keyVaultName: process.env.AZURE_KEYVAULT_NAME || 'idp-kv',
        serviceAccountRef: {
          name: 'external-secrets',  // Default SA name from ESO Helm chart
          namespace: 'external-secrets'
        }
      }
    },
    argocd: {
      syncWave: '-88',  // After ESO workload identity (-90), before secrets that use it
      labels: {
        'app.kubernetes.io/component': 'secret-store',
        'app.kubernetes.io/part-of': 'external-secrets',
        'app.kubernetes.io/name': 'cluster-secret-store'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  // Cert-Manager Secrets - Cloudflare API token from Azure Key Vault
  // Required by: cloudflare-issuer (ClusterIssuer)
  {
    name: 'cert-manager-secrets',
    namespace: 'cert-manager',
    clusterType: 'talos',  // Only needed on Talos for DNS-01 TLS challenges
    chart: {
      type: 'CertManagerSecretsChart',
      props: {
        namespace: 'cert-manager',
        syncWave: '-85',
        secretName: 'cloudflare-api-token-secret'
      }
    },
    argocd: {
      syncWave: '-85',  // After cluster-secret-store (-88), before cloudflare-issuer (-80)
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'cert-manager',
        'app.kubernetes.io/name': 'cert-manager-secrets'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Cloudflare ClusterIssuer - DNS-01 challenge for Let's Encrypt
  // Used by: Keycloak ingress (letsencrypt-cloudflare), Backstage ingress
  {
    name: 'cloudflare-issuer',
    namespace: 'cert-manager',
    clusterType: 'talos',  // Only needed on Talos for DNS-01 TLS challenges
    chart: {
      type: 'CloudflareIssuerChart',
      props: {
        email: 'admin@ai401kchat.com',
        issuerName: 'letsencrypt-cloudflare',
        cloudflareSecretName: 'cloudflare-api-token-secret',
        cloudflareSecretKey: 'api-token',
        syncWave: '-80',
        staging: false  // Use production Let's Encrypt
      }
    },
    argocd: {
      syncWave: '-80',  // After cert-manager-secrets (-85), before apps that need TLS
      labels: {
        'app.kubernetes.io/component': 'cluster-issuer',
        'app.kubernetes.io/part-of': 'cert-manager',
        'app.kubernetes.io/name': 'cloudflare-issuer'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
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

  // =========================================================================
  // Keycloak Identity Provider
  // Provides SSO/OIDC for Backstage, Argo Workflows, ArgoCD, Headlamp
  // =========================================================================

  // Keycloak Secrets - Creates ClusterSecretStores and password generators
  // This chart creates the 'keycloak' and 'gitea' ClusterSecretStores that allow
  // other namespaces to access secrets via ESO.
  {
    name: 'keycloak-secrets',
    namespace: 'keycloak',
    clusterType: 'both',  // Keycloak needed on both KIND and Talos
    chart: {
      type: 'KeycloakSecretsChart',
      props: {
        namespace: 'keycloak',
        syncWave: '-50'
      }
    },
    argocd: {
      syncWave: '-50',  // Before Keycloak deployment
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'keycloak',
        'app.kubernetes.io/name': 'keycloak-secrets'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Keycloak - KIND cluster (local development)
  {
    name: 'keycloak',
    namespace: 'keycloak',
    clusterType: 'kind',  // KIND uses local ingress
    chart: {
      type: 'KeycloakChart',
      props: {
        namespace: 'keycloak',
        hostname: 'cnoe.localtest.me',
        hostnamePort: 8443,
        ingressHosts: ['localhost', 'cnoe.localtest.me']
      }
    },
    dependencies: {
      keycloakSecrets: {
        type: 'KeycloakSecretsChart'
      }
    },
    argocd: {
      syncWave: '-45',  // After keycloak-secrets
      labels: {
        'app.kubernetes.io/component': 'identity-provider',
        'app.kubernetes.io/part-of': 'keycloak',
        'app.kubernetes.io/name': 'keycloak'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },

  // Keycloak - Talos cluster (production with TLS)
  {
    name: 'keycloak',
    namespace: 'keycloak',
    clusterType: 'talos',  // Talos uses public domain with TLS
    chart: {
      type: 'KeycloakChart',
      props: {
        namespace: 'keycloak',
        hostname: 'ai401kchat.com',
        hostnamePort: 443,
        httpRelativePath: '/keycloak',
        ingressHosts: ['ai401kchat.com'],
        tls: {
          enabled: true,
          secretName: 'keycloak-tls',
          clusterIssuer: 'letsencrypt-cloudflare'
        }
      }
    },
    dependencies: {
      keycloakSecrets: {
        type: 'KeycloakSecretsChart'
      }
    },
    argocd: {
      syncWave: '-45',  // After keycloak-secrets
      labels: {
        'app.kubernetes.io/component': 'identity-provider',
        'app.kubernetes.io/part-of': 'keycloak',
        'app.kubernetes.io/name': 'keycloak'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },

  // Keycloak Config - OIDC client configuration Job
  // Creates CNOE realm, users, and OIDC clients for Backstage/ArgoWF
  {
    name: 'keycloak-config',
    namespace: 'keycloak',
    clusterType: 'both',  // Config needed on both clusters
    chart: {
      type: 'KeycloakConfigChart',
      props: {
        namespace: 'keycloak',
        hostname: process.env.CLUSTER_TYPE === 'talos' ? 'ai401kchat.com' : 'cnoe.localtest.me',
        hostnamePort: process.env.CLUSTER_TYPE === 'talos' ? 443 : 8443
      }
    },
    dependencies: {
      keycloak: {
        type: 'KeycloakChart'
      }
    },
    argocd: {
      syncWave: '-40',  // After Keycloak deployment
      labels: {
        'app.kubernetes.io/component': 'configuration',
        'app.kubernetes.io/part-of': 'keycloak',
        'app.kubernetes.io/name': 'keycloak-config'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
    }
  },

  {
    name: 'keycloak-headlamp-client',
    namespace: 'keycloak',
    chart: {
      type: 'KeycloakHeadlampClientChart'
    },
    dependencies: {
      keycloakConfig: {
        type: 'KeycloakConfigChart'
      }
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

  // =========================================================================
  // Backstage Developer Portal
  // =========================================================================

  // Backstage Secrets - KIND cluster (local development)
  // Uses cnoe.localtest.me for OIDC and proxy URLs
  {
    name: 'backstage-secrets',
    namespace: 'backstage',
    clusterType: 'kind',
    chart: {
      type: 'BackstageSecretsChart',
      props: {
        namespace: 'backstage',
        baseHost: 'cnoe.localtest.me',
        syncWave: '-10'
      }
    },
    argocd: {
      syncWave: '-10',  // Deploy secrets before Backstage workloads
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-secrets'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },
  // Backstage Secrets - Talos cluster (production with public domain)
  // Uses ai401kchat.com for OIDC and proxy URLs
  {
    name: 'backstage-secrets',
    namespace: 'backstage',
    clusterType: 'talos',
    chart: {
      type: 'BackstageSecretsChart',
      props: {
        namespace: 'backstage',
        baseHost: 'ai401kchat.com',
        syncWave: '-10'
      }
    },
    argocd: {
      syncWave: '-10',  // Deploy secrets before Backstage workloads
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-secrets'
      },
      // Retry logic handles ESO webhook not being ready during initial cluster startup
      // ignoreDifferences prevents perpetual OutOfSync from controller-added fields
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },
  // Backstage Application - KIND cluster (local development)
  {
    name: 'backstage',
    namespace: 'backstage',
    clusterType: 'kind',  // KIND uses local ingress with cnoe.localtest.me
    chart: {
      type: 'BackstageChart',
      props: {
        namespace: 'backstage',
        ingressHosts: ['localhost', 'cnoe.localtest.me'],
      }
    },
    dependencies: {
      backstageSecrets: {
        type: 'BackstageSecretsChart'
      }
    },
    argocd: {
      syncWave: '20',  // After secrets (-10), PostgreSQL starts at sync-wave 10
      labels: {
        'app.kubernetes.io/component': 'developer-portal',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },
  // Backstage Application - Talos cluster (production with public domain)
  // Note: image v1.1.0+ uses environment variables for all URLs (OIDC, proxy, ArgoCD, etc.)
  // These are set via BackstageSecretsChart based on baseHost
  {
    name: 'backstage',
    namespace: 'backstage',
    clusterType: 'talos',  // Talos uses public domain with TLS via cert-manager
    chart: {
      type: 'BackstageChart',
      props: {
        namespace: 'backstage',
        ingressHosts: ['ai401kchat.com', 'www.ai401kchat.com'],
        tls: {
          enabled: true,
          secretName: 'backstage-tls',
          clusterIssuer: 'letsencrypt-cloudflare',
        },
        // proxyConfig removed - v1.1.0 image uses env vars from BackstageSecretsChart
      }
    },
    dependencies: {
      backstageSecrets: {
        type: 'BackstageSecretsChart'
      }
    },
    argocd: {
      syncWave: '20',  // After secrets (-10), PostgreSQL starts at sync-wave 10
      labels: {
        'app.kubernetes.io/component': 'developer-portal',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },
  // =========================================================================
  // Backstage Local Dev - Inner Loop (Kargo Pipeline Target)
  // This is a separate deployment for rapid iteration with Gitea images
  // =========================================================================
  {
    name: 'backstage-local-dev',
    namespace: 'backstage-local-dev',
    clusterType: 'kind',  // Only for KIND cluster (inner loop)
    chart: {
      type: 'BackstageChart',
      props: {
        namespace: 'backstage-local-dev',
        // Use the same image as production - Kargo will update the tag
        image: 'gitea.cnoe.localtest.me:8443/giteaadmin/backstage-cnoe:latest',
        imagePullSecretName: 'gitea-dockercfg',
        ingressHosts: ['backstage-local-dev.cnoe.localtest.me'],
      }
    },
    argocd: {
      syncWave: '25',  // After main backstage deployment
      // CRITICAL: Kargo authorization annotation
      // Allows Kargo stage 'backstage-local-dev' to update this application
      annotations: {
        'kargo.akuity.io/authorized-stage': 'kargo-pipelines:backstage-local-dev'
      },
      labels: {
        'app.kubernetes.io/component': 'developer-portal',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-local-dev',
        'kargo.akuity.io/loop': 'inner'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },
  // Backstage Local Dev Secrets - Inner Loop environment secrets (KIND)
  {
    name: 'backstage-local-dev-secrets',
    namespace: 'backstage-local-dev',
    clusterType: 'kind',
    chart: {
      type: 'BackstageSecretsChart',
      props: {
        namespace: 'backstage-local-dev',
        baseHost: 'cnoe.localtest.me',
        syncWave: '-10'
      }
    },
    argocd: {
      syncWave: '-10',  // Deploy secrets before Backstage workloads
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-local-dev-secrets'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },
  // Backstage Dev Secrets - Outer Loop environment secrets
  {
    name: 'backstage-dev-secrets',
    namespace: 'backstage-dev',
    clusterType: 'kind',
    chart: {
      type: 'BackstageSecretsChart',
      props: {
        namespace: 'backstage-dev',
        baseHost: 'cnoe.localtest.me',
        syncWave: '-10'
      }
    },
    argocd: {
      syncWave: '-10',  // Deploy secrets before Backstage workloads
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-dev-secrets'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },
  // Backstage Dev - Outer Loop (Kargo Pipeline Target)
  // This is a separate deployment for CI-built GHCR images
  {
    name: 'backstage-dev',
    namespace: 'backstage-dev',
    clusterType: 'kind',  // Deploy to KIND for outer loop dev stage
    chart: {
      type: 'BackstageChart',
      props: {
        namespace: 'backstage-dev',
        // Use GHCR image - Kargo will update the tag
        image: 'ghcr.io/pittampalliorg/backstage-cnoe:v1.1.0',
        ingressHosts: ['backstage-dev.cnoe.localtest.me'],
      }
    },
    argocd: {
      syncWave: '25',  // After secrets (-10), PostgreSQL starts at sync-wave 10
      // CRITICAL: Kargo authorization annotation
      // Allows Kargo stage 'backstage-dev' to update this application
      annotations: {
        'kargo.akuity.io/authorized-stage': 'kargo-pipelines:backstage-dev'
      },
      labels: {
        'app.kubernetes.io/component': 'developer-portal',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-dev',
        'kargo.akuity.io/loop': 'outer'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },
  // Backstage Staging - Outer Loop (Kargo Pipeline Target for Talos)
  // Manual promotion from dev stage to staging (Talos cluster)
  {
    name: 'backstage-staging',
    namespace: 'backstage-staging',
    clusterType: 'talos',  // Staging deploys to Talos cluster
    chart: {
      type: 'BackstageChart',
      props: {
        namespace: 'backstage-staging',
        // Use GHCR image - Kargo will update the tag
        image: 'ghcr.io/pittampalliorg/backstage:v1.0.0',
        ingressHosts: ['backstage-staging.ai401kchat.com'],
        tls: {
          enabled: true,
          secretName: 'backstage-staging-tls',
          clusterIssuer: 'letsencrypt-cloudflare',
        },
      }
    },
    dependencies: {
      backstageSecrets: {
        type: 'BackstageSecretsChart'
      }
    },
    argocd: {
      syncWave: '25',
      // CRITICAL: Kargo authorization annotation
      // Allows Kargo stage 'backstage-staging' to update this application
      annotations: {
        'kargo.akuity.io/authorized-stage': 'kargo-pipelines:backstage-staging'
      },
      labels: {
        'app.kubernetes.io/component': 'developer-portal',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-staging',
        'kargo.akuity.io/loop': 'outer'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },
  // Backstage Templates (Catalog entities for Backstage software templates)
  // This references existing entities directory, not synthesized manifests
  {
    name: 'backstage-templates',
    namespace: 'backstage',
    clusterType: 'both',  // Templates needed on both KIND and Talos clusters
    skipSynthesis: true,  // No chart synthesis - references existing entities directory
    sourcePath: 'entities',  // Override default 'manifests' path
    directoryExclude: 'catalog-info.yaml',  // Exclude catalog-info from sync
    argocd: {
      syncWave: '25',  // After Backstage application (20)
      labels: {
        'app.kubernetes.io/component': 'templates',
        'app.kubernetes.io/part-of': 'backstage',
        'app.kubernetes.io/name': 'backstage-templates'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
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
  // Kargo Backstage Pipeline - Progressive delivery for Backstage images
  // Inner Loop: Gitea → local-dev (rapid iteration)
  // Outer Loop: GHCR → dev → staging → production (CI-verified)
  {
    name: 'kargo-backstage-pipeline',
    namespace: 'kargo-pipelines',
    chart: {
      type: 'KargoBackstagePipelineChart',
      props: {
        enableInnerLoop: true,
        enableOuterLoop: true,
        enableStagingAndProdStages: false,
      }
    },
    dependencies: {
      kargoPipelinesProject: {
        type: 'KargoPipelinesProjectChart'
      }
    },
    argocd: {
      syncWave: '77',  // After project creation and credentials
      labels: {
        'app.kubernetes.io/component': 'pipeline',
        'app.kubernetes.io/part-of': 'kargo-pipelines',
        'app.kubernetes.io/name': 'kargo-backstage-pipeline'
      },
      syncPolicy: {
        automated: {
          prune: false,           // Don't delete Freight
          selfHeal: false         // Don't auto-revert manual changes
        },
        syncOptions: [
          'CreateNamespace=false',        // Namespace already exists
          'ApplyOutOfSyncOnly=true',      // Only sync changed resources
          'RespectIgnoreDifferences=true',
          'SkipDryRunOnMissingResource=true' // Skip dry-run for Kargo CRs
        ]
      },
      ignoreDifferences: [
        // Ignore status fields managed by Kargo controller
        { group: 'kargo.akuity.io', kind: 'Warehouse', jsonPointers: ['/status'] },
        { group: 'kargo.akuity.io', kind: 'Stage', jsonPointers: ['/status'] }
      ]
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
        serviceName: getTailscaleServiceName('k8s-api'),
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
        serviceName: getTailscaleServiceName('argocd'),  // Host-aware: svc:argocd-<host>
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
        serviceName: getTailscaleServiceName('langfuse'),  // Host-aware: svc:langfuse-<host>
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
        serviceName: getTailscaleServiceName('gitea'),  // Host-aware: svc:gitea-<host>
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
        serviceName: getTailscaleServiceName('kagent'),  // Host-aware: svc:kagent-<host>
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
        serviceName: getTailscaleServiceName('kargo'),  // Host-aware: svc:kargo-<host>
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
        serviceName: getTailscaleServiceName('headlamp'),  // Host-aware: svc:headlamp-<host>
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
        serviceName: getTailscaleServiceName('keycloak'),  // Host-aware: svc:keycloak-<host>
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

  // Backstage Tailscale Serve - Access: https://backstage.tail286401.ts.net
  // Primary developer portal access via Tailscale
  {
    name: 'backstage-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: getTailscaleServiceName('backstage'),  // Host-aware: svc:backstage-<host>
        backendHost: 'backstage.backstage.svc.cluster.local',
        backendPort: 7007,
        backendInsecure: false,
        persistentStorage: true,  // Persist certificates to avoid Let's Encrypt rate limits
        storageSize: '1Gi',
      }
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/name': 'backstage-tailscale-serve',
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

  // Observability Namespace - Both clusters
  {
    name: 'observability-namespace',
    namespace: 'observability',
    clusterType: 'both',  // Deploy to both KIND and Talos
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

  // Observability Secrets (from Azure Key Vault) - Both clusters
  {
    name: 'observability-secrets',
    namespace: 'observability',
    clusterType: 'both',  // Deploy to both KIND and Talos
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

  // Jaeger Distributed Tracing - KIND cluster (local development)
  {
    name: 'jaeger',
    namespace: 'observability',
    clusterType: 'kind',  // KIND uses cnoe.localtest.me
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

  // Jaeger Distributed Tracing - Talos cluster (production)
  {
    name: 'jaeger',
    namespace: 'observability',
    clusterType: 'talos',  // Talos uses public domain
    chart: {
      type: 'JaegerChart',
      props: {
        namespace: 'observability',
        imageVersion: '1.66.0',
        storageSize: '10Gi',
        spanStorageTtl: '168h',
        ingressHost: 'jaeger.ai401kchat.com'
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

  // Dapr Tracing Configuration (for SpecKit agents) - Both clusters
  {
    name: 'dapr-tracing-config',
    namespace: 'dapr-agents',
    clusterType: 'both',  // Deploy to both KIND and Talos
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
    clusterType: 'both',  // Deploy to both KIND and Talos
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

  // Dapr Runtime (Control Plane) - Both clusters
  {
    name: 'dapr-runtime',
    namespace: 'dapr-system',
    clusterType: 'both',  // Deploy to both KIND and Talos
    chart: {
      type: 'DaprRuntimeChart',
      props: {
        version: '1.16',
        enableHA: false,
        enableDashboard: true,
        enableDashboardIngress: false,  // Use Tailscale for access on Talos
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

  // Dapr Agents Redis (State and Pub/Sub backend) - Both clusters
  {
    name: 'dapr-agents-redis',
    namespace: 'dapr-agents',
    clusterType: 'both',  // Deploy to both KIND and Talos
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

  // Dapr Agents Secrets (LLM API keys from Azure Key Vault) - Both clusters
  {
    name: 'dapr-agents-secrets',
    namespace: 'dapr-agents',
    clusterType: 'both',  // Deploy to both KIND and Talos
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

  // Dapr Components (State stores, Pub/Sub, Conversation) - Both clusters
  {
    name: 'dapr-components',
    namespace: 'dapr-agents',
    clusterType: 'both',  // Deploy to both KIND and Talos
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
  },

  // =========================================================================
  // Hub-and-Spoke Architecture - Hub Cluster Applications
  // These apps deploy to the dedicated hub cluster for centralized management
  // =========================================================================

  // Hub Cluster: ESO Workload Identity Patch - Azure AD federation for external-secrets ServiceAccount
  // Required for ClusterSecretStore to authenticate with Azure Key Vault
  {
    name: 'hub-eso-workload-identity',
    namespace: 'external-secrets',
    clusterType: 'talos',  // Hub is a Talos cluster
    chart: {
      type: 'WorkloadIdentityPatchChart',
      props: {
        clientId: process.env.AZURE_CLIENT_ID || '',
        tenantId: process.env.AZURE_TENANT_ID || '',
        serviceAccountName: 'external-secrets',
        serviceAccountNamespace: 'external-secrets'
      }
    },
    argocd: {
      syncWave: '-90',  // Before cluster-secret-store
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'workload-identity',
        'app.kubernetes.io/part-of': 'hub-cluster',
        'app.kubernetes.io/name': 'hub-eso-workload-identity'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  // Hub Cluster: ClusterSecretStore - Azure Key Vault access
  // Required for syncing spoke credentials and other secrets to hub
  {
    name: 'hub-cluster-secret-store',
    namespace: 'external-secrets',
    clusterType: 'talos',
    chart: {
      type: 'ClusterSecretStoreChart',
      props: {
        storeName: 'azure-keyvault-store',
        keyVaultName: process.env.AZURE_KEYVAULT_NAME || 'idp-kv',
        serviceAccountRef: {
          name: 'external-secrets',
          namespace: 'external-secrets'
        }
      }
    },
    argocd: {
      syncWave: '-88',  // After ESO workload identity
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'secret-store',
        'app.kubernetes.io/part-of': 'hub-cluster',
        'app.kubernetes.io/name': 'hub-cluster-secret-store'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  // Hub Cluster: Tailscale CRDs - Required before Tailscale operator
  {
    name: 'hub-tailscale-crds',
    namespace: 'tailscale',
    clusterType: 'talos',
    chart: {
      type: 'TailscaleCrdsChart'
    },
    argocd: {
      syncWave: '-120',  // Deploy CRDs very early
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'hub-cluster',
        'app.kubernetes.io/name': 'hub-tailscale-crds'
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

  // Hub Cluster: Tailscale Operator Secrets (OAuth credentials from Azure Key Vault)
  {
    name: 'hub-tailscale-operator-secrets',
    namespace: 'tailscale',
    clusterType: 'talos',
    chart: {
      type: 'TailscaleOperatorSecretsChart',
      props: {
        namespace: 'tailscale',
        syncWave: '-85'
      }
    },
    argocd: {
      syncWave: '-85',  // After bootstrap-secrets, before operator
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/name': 'hub-tailscale-operator-secrets',
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'hub-cluster'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Hub Cluster: Tailscale Operator - Manages Tailscale connectivity
  {
    name: 'hub-tailscale-operator',
    namespace: 'tailscale',
    clusterType: 'talos',
    chart: {
      type: 'TailscaleOperatorChart',
      props: {
        version: '1.82.0',
        namespace: 'tailscale',
        operatorHostname: 'hub-operator',
        defaultTags: ['tag:k8s-operator'],
        enableApiServerProxy: true,
        tailnetAdmins: ['vpittamp@github']
      }
    },
    argocd: {
      syncWave: '-75',  // After operator secrets
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/name': 'hub-tailscale-operator',
        'app.kubernetes.io/component': 'operator',
        'app.kubernetes.io/part-of': 'hub-cluster'
      },
      syncPolicy: automatedSyncWithOptions(['CreateNamespace=true', 'ServerSideApply=true'])
    }
  },

  // Hub Cluster: Tailscale Secrets (Auth key for Tailscale Services pods)
  {
    name: 'hub-tailscale-secrets',
    namespace: 'tailscale',
    clusterType: 'talos',
    chart: {
      type: 'TailscaleSecretsChart',
      props: {
        namespace: 'tailscale',
        syncWave: '-70'
      }
    },
    argocd: {
      syncWave: '-70',  // Before tailscale serve pods
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/name': 'hub-tailscale-secrets',
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'hub-cluster'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Hub Cluster: ArgoCD Tailscale Serve - Access: https://argocd-hub.<tailnet>.ts.net
  // Provides remote access to hub ArgoCD UI via Tailscale
  {
    name: 'hub-argocd-tailscale-serve',
    namespace: 'tailscale',
    clusterType: 'talos',
    chart: {
      type: 'TailscaleServeChart',
      props: {
        serviceName: 'argocd-hub',  // Stable URL: argocd-hub.tail286401.ts.net
        backendHost: 'argocd-server.argocd.svc.cluster.local',
        backendPort: 443,
        backendInsecure: true,
        persistentStorage: true,
        storageSize: '1Gi'
      }
    },
    argocd: {
      syncWave: '-60',  // After auth key secret
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/name': 'hub-argocd-tailscale-serve',
        'app.kubernetes.io/component': 'tailscale-serve',
        'app.kubernetes.io/part-of': 'hub-cluster'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // Hub Cluster: Kubernetes API Tailscale Serve - Access: https://k8s-api-hub.<tailnet>.ts.net
  // Provides remote kubectl access to hub cluster via Tailscale
  {
    name: 'hub-k8s-api-tailscale-serve',
    namespace: 'tailscale',
    clusterType: 'talos',
    chart: {
      type: 'K8sApiTailscaleServeChart',
      props: {
        serviceName: 'k8s-api-hub',
        authKeySecretName: 'tailscale-auth-key',
        tailnetName: 'tail286401',
        createStaticTokenSecret: true,
        remoteAccessTokenSecretName: 'hub-k8s-remote-access-token'
      }
    },
    argocd: {
      syncWave: '-60',
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/name': 'hub-k8s-api-tailscale-serve',
        'app.kubernetes.io/component': 'api-proxy',
        'app.kubernetes.io/part-of': 'hub-cluster'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true }
      }
    }
  },

  // =========================================================================
  // Hub-and-Spoke Architecture - Spoke Cluster Registration
  // ExternalSecrets sync spoke credentials from Azure Key Vault
  // Cluster secrets register spokes in ArgoCD
  // =========================================================================

  // Hetzner Spoke: ExternalSecret for credentials
  {
    name: 'spoke-credentials-hetzner',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterCredentialsChart',
      props: {
        clusterName: 'hetzner',
        keyVaultSecretPrefix: 'ARGOCD-CLUSTER-HETZNER'
      }
    },
    argocd: {
      syncWave: '-82',  // After ClusterSecretStore
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'credentials',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-credentials-hetzner',
        'cluster-host': 'hetzner'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Thinkpad Spoke: ExternalSecret for credentials
  {
    name: 'spoke-credentials-thinkpad',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterCredentialsChart',
      props: {
        clusterName: 'thinkpad',
        keyVaultSecretPrefix: 'ARGOCD-CLUSTER-THINKPAD'
      }
    },
    argocd: {
      syncWave: '-82',
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'credentials',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-credentials-thinkpad',
        'cluster-host': 'thinkpad'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Ryzen Spoke: ExternalSecret for credentials
  {
    name: 'spoke-credentials-ryzen',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterCredentialsChart',
      props: {
        clusterName: 'ryzen',
        keyVaultSecretPrefix: 'ARGOCD-CLUSTER-RYZEN'
      }
    },
    argocd: {
      syncWave: '-82',
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'credentials',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-credentials-ryzen',
        'cluster-host': 'ryzen'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Talos Spoke: ExternalSecret for credentials
  {
    name: 'spoke-credentials-talos',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterCredentialsChart',
      props: {
        clusterName: 'talos',
        keyVaultSecretPrefix: 'ARGOCD-CLUSTER-TALOS'
      }
    },
    argocd: {
      syncWave: '-82',
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'credentials',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-credentials-talos',
        'cluster-host': 'talos'
      },
      syncPolicy: externalSecretsAppSyncPolicy(),
      ignoreDifferences: EXTERNAL_SECRET_IGNORE_DIFFERENCES
    }
  },

  // Hetzner Spoke: ArgoCD Cluster Secret
  {
    name: 'spoke-cluster-hetzner',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterSecretChart',
      props: {
        clusterName: 'hetzner',
        credentialsSecretName: 'spoke-creds-hetzner'
      }
    },
    argocd: {
      syncWave: '-80',  // After ExternalSecret syncs credentials
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'cluster-secret',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-cluster-hetzner',
        'cluster-host': 'hetzner'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  // Thinkpad Spoke: ArgoCD Cluster Secret
  {
    name: 'spoke-cluster-thinkpad',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterSecretChart',
      props: {
        clusterName: 'thinkpad',
        credentialsSecretName: 'spoke-creds-thinkpad'
      }
    },
    argocd: {
      syncWave: '-80',
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'cluster-secret',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-cluster-thinkpad',
        'cluster-host': 'thinkpad'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  // Ryzen Spoke: ArgoCD Cluster Secret
  {
    name: 'spoke-cluster-ryzen',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterSecretChart',
      props: {
        clusterName: 'ryzen',
        credentialsSecretName: 'spoke-creds-ryzen'
      }
    },
    argocd: {
      syncWave: '-80',
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'cluster-secret',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-cluster-ryzen',
        'cluster-host': 'ryzen'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  // Talos Spoke: ArgoCD Cluster Secret
  {
    name: 'spoke-cluster-talos',
    namespace: 'argocd',
    clusterType: 'talos',
    chart: {
      type: 'ArgocdClusterSecretChart',
      props: {
        clusterName: 'talos',
        credentialsSecretName: 'spoke-creds-talos'
      }
    },
    argocd: {
      syncWave: '-80',
      targetCluster: 'hub',
      labels: {
        'app.kubernetes.io/component': 'cluster-secret',
        'app.kubernetes.io/part-of': 'spoke-registration',
        'app.kubernetes.io/name': 'spoke-cluster-talos',
        'cluster-host': 'talos'
      },
      syncPolicy: automatedSyncWithOptions(['ServerSideApply=true'])
    }
  },

  // =========================================================================
  // Hub-and-Spoke Architecture - Cross-Cluster Application Deployments
  // Example applications targeting spoke clusters via hub ArgoCD
  // =========================================================================

  // Example: Backstage Dev Environment on Thinkpad Spoke
  // Demonstrates cross-cluster deployment using targetCluster field
  {
    name: 'backstage-dev-spoke',
    namespace: 'backstage',
    clusterType: 'talos',
    chart: {
      type: 'NamespaceChart',  // Just the namespace for demo
      props: {
        namespace: 'backstage'
      }
    },
    argocd: {
      syncWave: '50',  // Deploy after spoke registration
      targetCluster: 'thinkpad',  // Deploy to thinkpad spoke cluster
      labels: {
        'app.kubernetes.io/name': 'backstage-dev-spoke',
        'app.kubernetes.io/component': 'application',
        'app.kubernetes.io/part-of': 'cross-cluster-demo',
        'app.kubernetes.io/environment': 'dev'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true']
      }
    }
  },

  // Example: Backstage Prod Environment on Talos Spoke
  // Demonstrates production deployment to separate cluster
  {
    name: 'backstage-prod-spoke',
    namespace: 'backstage',
    clusterType: 'talos',
    chart: {
      type: 'NamespaceChart',  // Just the namespace for demo
      props: {
        namespace: 'backstage'
      }
    },
    argocd: {
      syncWave: '50',
      targetCluster: 'talos',  // Deploy to talos spoke cluster
      labels: {
        'app.kubernetes.io/name': 'backstage-prod-spoke',
        'app.kubernetes.io/component': 'application',
        'app.kubernetes.io/part-of': 'cross-cluster-demo',
        'app.kubernetes.io/environment': 'production'
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true']
      }
    }
  }
];
