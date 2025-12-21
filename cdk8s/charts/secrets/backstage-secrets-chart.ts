import { Construct } from 'constructs';
import { Chart, ChartProps, JsonPatch } from 'cdk8s';
import * as k8s from '../../imports/k8s';
import {
  ExternalSecret,
  ClusterSecretStore,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecTargetTemplateEngineVersion,
  ExternalSecretSpecDataFromSourceRefGeneratorRefKind,
  ClusterSecretStoreSpecProviderKubernetesServerCaProviderType,
} from '../../imports/external-secrets.io';
import { Password } from '../../imports/generators.external-secrets.io';

export interface BackstageSecretsChartProps extends ChartProps {
  // Namespace for Backstage secrets (default: backstage)
  namespace?: string;
  // Base host for Backstage URLs (default: cnoe.localtest.me)
  baseHost?: string;
  // Sync wave for ArgoCD ordering (default: -10)
  syncWave?: string;
}

/**
 * BackstageSecretsChart - External Secrets for Backstage
 *
 * Creates 10 resources:
 * 1. Password generator: backstage (36 chars)
 * 2. Password generator: backstage-session (64 chars)
 * 3. ExternalSecret: backstage-oidc → backstage-env-vars Secret
 * 4. ExternalSecret: gitea-credentials
 * 5. ExternalSecret: ghcr-dockercfg-external
 * 6. ExternalSecret: argocd-credentials
 * 7. ServiceAccount: eso-store (in argocd namespace)
 * 8. Role: eso-store (in argocd namespace)
 * 9. RoleBinding: eso-store (in argocd namespace)
 * 10. ClusterSecretStore: argocd
 */
export class BackstageSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: BackstageSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace ?? 'backstage';
    const baseHost = props.baseHost ?? process.env.INGRESS_HOST ?? 'cnoe.localtest.me';
    const syncWave = props.syncWave ?? '-10';
    const clusterHost = process.env.CLUSTER_HOST || 'localdev';

    // ==========================================================================
    // Password Generators
    // ==========================================================================

    // Password generator: backstage (36 chars for PostgreSQL password)
    new Password(this, 'backstage-password', {
      metadata: {
        name: 'backstage',
        namespace,
      },
      spec: {
        length: 36,
        digits: 5,
        symbols: 5,
        symbolCharacters: '/-+',
        noUpper: false,
        allowRepeat: true,
      },
    });

    // Password generator: backstage-session (64 chars for session secret)
    new Password(this, 'backstage-session-password', {
      metadata: {
        name: 'backstage-session',
        namespace,
      },
      spec: {
        length: 64,
        digits: 10,
        symbols: 10,
        symbolCharacters: '/-+=',
        noUpper: false,
        allowRepeat: true,
      },
    });

    // ==========================================================================
    // ExternalSecrets
    // ==========================================================================

    // Determine Keycloak metadata URL based on baseHost
    // KIND (cnoe.localtest.me): Use external URL - CoreDNS rewrites to ingress-nginx
    // Talos (any other domain): Use internal cluster URL to avoid DNS issues
    const isKind = baseHost === 'cnoe.localtest.me';
    const keycloakMetadataUrl = isKind
      ? `https://${baseHost}:8443/keycloak/realms/cnoe/.well-known/openid-configuration`
      : 'http://keycloak.keycloak.svc.cluster.local:8080/keycloak/realms/cnoe/.well-known/openid-configuration';

    // Compute environment-specific URLs
    // For KIND: use external URLs with port 8443
    // For Talos/other: use external URLs with proper domain
    const portSuffix = isKind ? ':8443' : '';
    const giteaHost = isKind ? `gitea.${baseHost}${portSuffix}` : `gitea.${baseHost}`;
    const giteaHostNoPort = isKind ? `gitea.${baseHost}` : `gitea.${baseHost}`;
    // Agent Forge (A2A) endpoint:
    // - KIND: use the in-cluster kagent service (Backstage reaches it via backend proxy)
    // - Talos: use the external host
    const agentForgeUrl = isKind
      ? 'http://k8s-agent.kagent:8080'
      : `https://ai-platform-engineering.${baseHost}${portSuffix}`;

    // ExternalSecret: backstage-oidc → backstage-env-vars Secret
    // Uses keycloak ClusterSecretStore + Password generators
    new ExternalSecret(this, 'backstage-oidc', {
      metadata: {
        name: 'backstage-oidc',
        namespace,
      },
      spec: {
        secretStoreRef: {
          name: 'keycloak',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        refreshInterval: '0',
        target: {
          name: 'backstage-env-vars',
          template: {
            engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
            data: {
              // Core Backstage URLs
              'BACKSTAGE_FRONTEND_URL': `https://${baseHost}${portSuffix}/backstage`,
              // PostgreSQL - use namespace for service discovery
              'POSTGRES_HOST': `postgresql.${namespace}.svc.cluster.local`,
              'POSTGRES_PORT': '5432',
              'POSTGRES_DB': 'backstage',
              'POSTGRES_USER': 'backstage',
              'POSTGRES_PASSWORD': '{{.POSTGRES_PASSWORD}}',
              'BACKSTAGE_SESSION_SECRET': '{{.SESSION_SECRET}}',
              // ArgoCD & Argo Workflows
              'ARGO_WORKFLOWS_URL': `https://${baseHost}${portSuffix}/argo-workflows`,
              'ARGO_CD_URL': `https://argocd.${baseHost}${portSuffix}`,
              'ARGOCD_AUTH_TOKEN': 'argocd.token={{.ARGOCD_SESSION_TOKEN}}',
              // Keycloak OIDC
              'KEYCLOAK_NAME_METADATA': keycloakMetadataUrl,
              'KEYCLOAK_CLIENT_SECRET': '{{.BACKSTAGE_CLIENT_SECRET}}',
              // Gitea integration
              'GITEA_URL': `https://${giteaHost}`,
              'GITEA_HOST': giteaHost,
              'GITEA_URL_NO_PORT': `https://${giteaHostNoPort}`,
              'GITEA_HOST_NO_PORT': giteaHostNoPort,
              // Proxy targets
              'AGENT_FORGE_URL': agentForgeUrl,
              'KARGO_URL': `https://kargo.${baseHost}${portSuffix}`,
              // Catalog URL
              'CATALOG_URL': `https://${giteaHost}/giteaAdmin/idpbuilder-${clusterHost}-backstage-templates-entities/src/branch/main/catalog-info.yaml`,
            },
          },
        },
        data: [
          {
            secretKey: 'ARGOCD_SESSION_TOKEN',
            remoteRef: {
              key: 'keycloak-clients',
              property: 'ARGOCD_SESSION_TOKEN',
            },
          },
          {
            secretKey: 'BACKSTAGE_CLIENT_SECRET',
            remoteRef: {
              key: 'keycloak-clients',
              property: 'BACKSTAGE_CLIENT_SECRET',
            },
          },
        ],
        dataFrom: [
          {
            sourceRef: {
              generatorRef: {
                apiVersion: 'generators.external-secrets.io/v1alpha1',
                kind: ExternalSecretSpecDataFromSourceRefGeneratorRefKind.PASSWORD,
                name: 'backstage',
              },
            },
            rewrite: [
              {
                transform: {
                  template: 'POSTGRES_PASSWORD',
                },
              },
            ],
          },
          {
            sourceRef: {
              generatorRef: {
                apiVersion: 'generators.external-secrets.io/v1alpha1',
                kind: ExternalSecretSpecDataFromSourceRefGeneratorRefKind.PASSWORD,
                name: 'backstage-session',
              },
            },
            rewrite: [
              {
                transform: {
                  template: 'SESSION_SECRET',
                },
              },
            ],
          },
        ],
      },
    });

    // ExternalSecret: gitea-credentials
    new ExternalSecret(this, 'gitea-credentials', {
      metadata: {
        name: 'gitea-credentials',
        namespace,
      },
      spec: {
        secretStoreRef: {
          name: 'gitea',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        refreshInterval: '0',
        target: {
          name: 'gitea-credentials',
        },
        data: [
          {
            secretKey: 'GITEA_USERNAME',
            remoteRef: {
              key: 'gitea-credential',
              property: 'username',
            },
          },
          {
            secretKey: 'GITEA_PASSWORD',
            remoteRef: {
              key: 'gitea-credential',
              property: 'password',
            },
          },
        ],
      },
    });

    // ExternalSecret: gitea-dockercfg-external (pull secret for the in-cluster Gitea OCI registry)
    const giteaDockerCfg = new ExternalSecret(this, 'gitea-dockercfg-external', {
      metadata: {
        name: 'gitea-dockercfg-external',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'gitea-dockercfg',
          'app.kubernetes.io/part-of': 'backstage',
        },
      },
      spec: {
        refreshInterval: '0',
        secretStoreRef: {
          name: 'gitea',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'gitea-dockercfg',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'kubernetes.io/dockerconfigjson',
            data: {
              '.dockerconfigjson': `{
  "auths": {
    "${giteaHost}": {
      "username": "{{ .username }}",
      "password": "{{ .password }}",
      "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
    }
  }
}`,
            },
          },
        },
        data: [
          {
            secretKey: 'username',
            remoteRef: {
              key: 'gitea-credential',
              property: 'username',
            },
          },
          {
            secretKey: 'password',
            remoteRef: {
              key: 'gitea-credential',
              property: 'password',
            },
          },
        ],
      },
    });
    giteaDockerCfg.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ExternalSecret: ghcr-dockercfg-external (with sync-wave -10)
    const ghcrDockerCfg = new ExternalSecret(this, 'ghcr-dockercfg-external', {
      metadata: {
        name: 'ghcr-dockercfg-external',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'ghcr-dockercfg',
          'app.kubernetes.io/part-of': 'backstage',
        },
      },
      spec: {
        refreshInterval: '1h',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'ghcr-dockercfg',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'kubernetes.io/dockerconfigjson',
            data: {
              '.dockerconfigjson': `{
  "auths": {
    "ghcr.io": {
      "username": "pittampalliorg",
      "password": "{{ .pat }}",
      "auth": "{{ printf "%s:%s" "pittampalliorg" .pat | b64enc }}"
    }
  }
}`,
            },
          },
        },
        data: [
          {
            secretKey: 'pat',
            remoteRef: {
              key: 'GITHUB-PAT',
            },
          },
        ],
      },
    });
    ghcrDockerCfg.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ==========================================================================
    // ArgoCD ClusterSecretStore Resources (in argocd namespace)
    // ==========================================================================

    // ServiceAccount: eso-store (in argocd namespace)
    new k8s.KubeServiceAccount(this, 'eso-store-sa', {
      metadata: {
        name: 'eso-store',
        namespace: 'argocd',
      },
    });

    // Role: eso-store (in argocd namespace)
    new k8s.KubeRole(this, 'eso-store-role', {
      metadata: {
        name: 'eso-store',
        namespace: 'argocd',
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['authorization.k8s.io'],
          resources: ['selfsubjectrulesreviews'],
          verbs: ['create'],
        },
      ],
    });

    // RoleBinding: eso-store (in argocd namespace)
    new k8s.KubeRoleBinding(this, 'eso-store-rolebinding', {
      metadata: {
        name: 'eso-store',
        namespace: 'argocd',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'eso-store',
          namespace: 'argocd',
        },
      ],
      roleRef: {
        kind: 'Role',
        name: 'eso-store',
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // ClusterSecretStore: argocd (Kubernetes provider)
    new ClusterSecretStore(this, 'argocd-clustersecretstore', {
      metadata: {
        name: 'argocd',
      },
      spec: {
        provider: {
          kubernetes: {
            remoteNamespace: 'argocd',
            server: {
              caProvider: {
                type: ClusterSecretStoreSpecProviderKubernetesServerCaProviderType.CONFIG_MAP,
                name: 'kube-root-ca.crt',
                namespace: 'argocd',
                key: 'ca.crt',
              },
            },
            auth: {
              serviceAccount: {
                name: 'eso-store',
                namespace: 'argocd',
              },
            },
          },
        },
      },
    });

    // ExternalSecret: argocd-credentials
    new ExternalSecret(this, 'argocd-credentials', {
      metadata: {
        name: 'argocd-credentials',
        namespace,
      },
      spec: {
        secretStoreRef: {
          name: 'argocd',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        refreshInterval: '0',
        target: {
          name: 'argocd-credentials',
        },
        data: [
          {
            secretKey: 'ARGOCD_ADMIN_PASSWORD',
            remoteRef: {
              key: 'argocd-initial-admin-secret',
              property: 'password',
            },
          },
        ],
      },
    });
  }
}
