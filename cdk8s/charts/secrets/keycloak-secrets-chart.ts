/**
 * KeycloakSecretsChart - External Secrets for Keycloak
 *
 * This chart creates the secrets infrastructure for Keycloak:
 * - Password generators for admin, database, and user credentials
 * - ExternalSecret that creates the keycloak-config secret
 * - ClusterSecretStore for accessing keycloak secrets from other namespaces
 * - RBAC for the ClusterSecretStore service account
 *
 * Constitution Alignment:
 * - Principle V (External Secrets Management): Uses ESO Password generators
 * - Principle VI (External Secrets Management): Creates ClusterSecretStore
 */

import { Construct } from 'constructs';
import { Chart, ChartProps } from 'cdk8s';
import * as k8s from '../../imports/k8s';
import {
  ExternalSecret,
  ClusterSecretStore,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecDataFromSourceRefGeneratorRefKind,
  ExternalSecretSpecTargetTemplateEngineVersion,
  ClusterSecretStoreSpecProviderKubernetesServerCaProviderType,
} from '../../imports/external-secrets.io';
import { Password } from '../../imports/generators.external-secrets.io';
import { addExternalSecretsWebhookGate } from '../../lib/external-secrets-hooks';

export interface KeycloakSecretsChartProps extends ChartProps {
  /**
   * Namespace for Keycloak secrets (default: keycloak)
   */
  namespace?: string;

  /**
   * Sync wave for ArgoCD ordering (default: -10)
   */
  syncWave?: string;
}

/**
 * KeycloakSecretsChart - External Secrets for Keycloak
 *
 * Creates resources:
 * 1. Password generator: keycloak (36 chars)
 * 2. ExternalSecret: keycloak-config → keycloak-config Secret
 * 3. ServiceAccount: eso-store (in keycloak namespace)
 * 4. Role: eso-store (in keycloak namespace)
 * 5. RoleBinding: eso-store (in keycloak namespace)
 * 6. ClusterSecretStore: keycloak (Kubernetes provider)
 *
 * Also creates the Gitea ClusterSecretStore infrastructure:
 * 7. ServiceAccount: eso-store (in gitea namespace)
 * 8. Role: eso-store (in gitea namespace)
 * 9. RoleBinding: eso-store (in gitea namespace)
 * 10. ClusterSecretStore: gitea (Kubernetes provider)
 */
export class KeycloakSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: KeycloakSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace ?? 'keycloak';
    const syncWave = props.syncWave ?? '-10';

    addExternalSecretsWebhookGate(this, namespace);

    // ==========================================================================
    // Password Generator
    // ==========================================================================

    new Password(this, 'keycloak-password', {
      metadata: {
        name: 'keycloak',
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
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

    // ==========================================================================
    // ExternalSecret: keycloak-config
    // Uses Password generator for credentials
    // ==========================================================================

    new ExternalSecret(this, 'keycloak-config-es', {
      metadata: {
        name: 'keycloak-config',
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        refreshInterval: '0',
        target: {
          name: 'keycloak-config',
          template: {
            metadata: {
              labels: {
                'cnoe.io/cli-secret': 'true',
                'cnoe.io/package-name': 'keycloak',
              },
            },
            engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
            data: {
              KEYCLOAK_ADMIN_PASSWORD: '{{.KEYCLOAK_ADMIN_PASSWORD}}',
              KC_DB_USERNAME: 'keycloak',
              KC_DB_PASSWORD: '{{.KC_DB_PASSWORD}}',
              POSTGRES_DB: 'keycloak',
              POSTGRES_USER: 'keycloak',
              POSTGRES_PASSWORD: '{{.KC_DB_PASSWORD}}',
              USER_PASSWORD: '{{.USER_PASSWORD}}',
            },
          },
        },
        dataFrom: [
          {
            sourceRef: {
              generatorRef: {
                apiVersion: 'generators.external-secrets.io/v1alpha1',
                kind: ExternalSecretSpecDataFromSourceRefGeneratorRefKind.PASSWORD,
                name: 'keycloak',
              },
            },
            rewrite: [
              {
                transform: {
                  template: 'KEYCLOAK_ADMIN_PASSWORD',
                },
              },
            ],
          },
          {
            sourceRef: {
              generatorRef: {
                apiVersion: 'generators.external-secrets.io/v1alpha1',
                kind: ExternalSecretSpecDataFromSourceRefGeneratorRefKind.PASSWORD,
                name: 'keycloak',
              },
            },
            rewrite: [
              {
                transform: {
                  template: 'KC_DB_PASSWORD',
                },
              },
            ],
          },
          {
            sourceRef: {
              generatorRef: {
                apiVersion: 'generators.external-secrets.io/v1alpha1',
                kind: ExternalSecretSpecDataFromSourceRefGeneratorRefKind.PASSWORD,
                name: 'keycloak',
              },
            },
            rewrite: [
              {
                transform: {
                  template: 'USER_PASSWORD',
                },
              },
            ],
          },
        ],
      },
    });

    // ==========================================================================
    // ClusterSecretStore: keycloak (Kubernetes provider)
    // Allows other namespaces to access secrets in keycloak namespace
    // ==========================================================================

    // ServiceAccount for ESO store (keycloak namespace)
    // Note: Using unique name 'eso-store-keycloak' to avoid CDK8s filename collision with gitea's eso-store
    new k8s.KubeServiceAccount(this, 'keycloak-eso-store-sa', {
      metadata: {
        name: 'eso-store-keycloak',
        namespace,
      },
    });

    // Role for accessing secrets (keycloak namespace)
    new k8s.KubeRole(this, 'keycloak-eso-store-role', {
      metadata: {
        name: 'eso-store-keycloak',
        namespace,
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

    // RoleBinding (keycloak namespace)
    new k8s.KubeRoleBinding(this, 'keycloak-eso-store-rolebinding', {
      metadata: {
        name: 'eso-store-keycloak',
        namespace,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'eso-store-keycloak',
          namespace,
        },
      ],
      roleRef: {
        kind: 'Role',
        name: 'eso-store-keycloak',
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // ClusterSecretStore (uses keycloak-specific ServiceAccount)
    new ClusterSecretStore(this, 'keycloak-clustersecretstore', {
      metadata: {
        name: 'keycloak',
      },
      spec: {
        provider: {
          kubernetes: {
            remoteNamespace: namespace,
            server: {
              caProvider: {
                type: ClusterSecretStoreSpecProviderKubernetesServerCaProviderType.CONFIG_MAP,
                name: 'kube-root-ca.crt',
                namespace,
                key: 'ca.crt',
              },
            },
            auth: {
              serviceAccount: {
                name: 'eso-store-keycloak',
                namespace,
              },
            },
          },
        },
      },
    });

    // ==========================================================================
    // ClusterSecretStore: gitea (Kubernetes provider)
    // For accessing idpbuilder-created Gitea secrets
    // ==========================================================================

    const giteaNamespace = 'gitea';

    // Create gitea namespace if it doesn't exist (needed for ClusterSecretStore RBAC)
    // On KIND with idpbuilder, this namespace is created automatically
    // On Talos/external clusters, we need to create it
    new k8s.KubeNamespace(this, 'gitea-namespace', {
      metadata: {
        name: giteaNamespace,
      },
    });

    // ServiceAccount for ESO store in gitea namespace
    new k8s.KubeServiceAccount(this, 'gitea-eso-store-sa', {
      metadata: {
        name: 'eso-store',
        namespace: giteaNamespace,
      },
    });

    // Role for accessing secrets
    new k8s.KubeRole(this, 'gitea-eso-store-role', {
      metadata: {
        name: 'eso-store',
        namespace: giteaNamespace,
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

    // RoleBinding
    new k8s.KubeRoleBinding(this, 'gitea-eso-store-rolebinding', {
      metadata: {
        name: 'eso-store',
        namespace: giteaNamespace,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'eso-store',
          namespace: giteaNamespace,
        },
      ],
      roleRef: {
        kind: 'Role',
        name: 'eso-store',
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // ClusterSecretStore for gitea
    new ClusterSecretStore(this, 'gitea-clustersecretstore', {
      metadata: {
        name: 'gitea',
      },
      spec: {
        provider: {
          kubernetes: {
            remoteNamespace: giteaNamespace,
            server: {
              caProvider: {
                type: ClusterSecretStoreSpecProviderKubernetesServerCaProviderType.CONFIG_MAP,
                name: 'kube-root-ca.crt',
                namespace: giteaNamespace,
                key: 'ca.crt',
              },
            },
            auth: {
              serviceAccount: {
                name: 'eso-store',
                namespace: giteaNamespace,
              },
            },
          },
        },
      },
    });
  }
}
