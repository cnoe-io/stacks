import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { 
  ExternalSecret,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecTargetTemplateEngineVersion,
  ExternalSecretSpecDataRemoteRefConversionStrategy,
  ExternalSecretSpecDataRemoteRefDecodingStrategy,
  ExternalSecretSpecDataRemoteRefMetadataPolicy,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecDataFromSourceRefGeneratorRefKind
} from '../../imports/external-secrets.io';
import { Password } from '../../imports/generators.external-secrets.io';
import { JsonPatch } from 'cdk8s';
import { createDockerConfigJsonExternalSecret } from '../../lib/eso-helpers';

export interface BackstageSecretsChartProps extends ChartProps {
  // Additional props can be added here as needed
}

export class BackstageSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: BackstageSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = 'backstage';

    // Note: ClusterSecretStore 'azure-keyvault-store' is created by bootstrap
    // We just reference it here

    // ---------------------------------------------------------------------
    // Password generators for database credentials and session secret
    // ---------------------------------------------------------------------

    new Password(this, 'backstage-postgres-password', {
      metadata: {
        name: 'backstage',
        namespace
      },
      spec: {
        length: 36,
        digits: 5,
        symbols: 5,
        symbolCharacters: '/-+',
        noUpper: false,
        allowRepeat: true
      }
    });

    new Password(this, 'backstage-session-password', {
      metadata: {
        name: 'backstage-session',
        namespace
      },
      spec: {
        length: 48,
        digits: 6,
        symbols: 4,
        symbolCharacters: '/-+',
        noUpper: false,
        allowRepeat: true
      }
    });

    // ---------------------------------------------------------------------
    // GitHub Container Registry Credentials for pulling private images
    // ---------------------------------------------------------------------
    const ghcr = createDockerConfigJsonExternalSecret(this, 'ghcr-dockercfg-external', {
      name: 'ghcr-dockercfg',
      namespace,
      registry: 'ghcr.io',
      usernameTemplate: 'pittampalliorg',
      passwordKey: 'GITHUB-PAT',
      refreshInterval: '1h',
      secretStoreRef: { name: 'azure-keyvault-store', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
    });
    ghcr.addJsonPatch(
      JsonPatch.add('/metadata/labels', {
        'app.kubernetes.io/name': 'ghcr-dockercfg',
        'app.kubernetes.io/part-of': 'backstage',
      }),
    );
    ghcr.addJsonPatch(
      JsonPatch.add('/metadata/annotations', {
        'argocd.argoproj.io/sync-wave': '-10',
      }),
    );

    // ---------------------------------------------------------------------
    // SSH Keys for Development Access
    // ---------------------------------------------------------------------
    
    // SSH Authorized Keys from Azure Key Vault (for each environment)
    ['dev', 'staging'].forEach(envName => {
      new ExternalSecret(this, `${envName}-ssh-keys-external`, {
        metadata: {
          name: `backstage-ssh-keys-${envName}`,
          namespace: namespace,
          labels: {
            app: `backstage-${envName}`,
            environment: envName,
            purpose: 'ssh-keys'
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
    });

    // ---------------------------------------------------------------------
    // Core Backstage environment configuration (OIDC, database, tokens)
    // ---------------------------------------------------------------------

    new ExternalSecret(this, 'backstage-env-vars-external', {
      metadata: {
        name: 'backstage-oidc',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'backstage-env-vars',
          'app.kubernetes.io/part-of': 'backstage'
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '70'
        }
      },
      spec: {
        refreshInterval: '0',
        secretStoreRef: {
          name: 'keycloak',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
        },
        target: {
          name: 'backstage-env-vars',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
            data: {
              BACKSTAGE_FRONTEND_URL: 'https://backstage.cnoe.localtest.me:8443',
              POSTGRES_HOST: 'postgresql.backstage.svc.cluster.local',
              POSTGRES_PORT: '5432',
              POSTGRES_DB: 'backstage',
              POSTGRES_USER: 'backstage',
              POSTGRES_PASSWORD: 'changeme123',
              BACKSTAGE_SESSION_SECRET: '{{ .SESSION_SECRET }}',
              ARGO_WORKFLOWS_URL: 'https://cnoe.localtest.me:8443/argo-workflows',
              KEYCLOAK_NAME_METADATA: 'https://cnoe.localtest.me:8443/keycloak/realms/cnoe/.well-known/openid-configuration',
              KEYCLOAK_CLIENT_SECRET: '{{ .BACKSTAGE_CLIENT_SECRET }}',
              ARGOCD_AUTH_TOKEN: 'argocd.token={{ .ARGOCD_SESSION_TOKEN }}',
              ARGO_CD_URL: 'https://argocd-server.argocd.svc.cluster.local/api/v1/',
              BACKSTAGE_SERVICE_TOKEN: '46Y8Je+VWx4djespJvjKg7Q1FKKE7eBM'
            }
          }
        },
        data: [
          {
            secretKey: 'ARGOCD_SESSION_TOKEN',
            remoteRef: {
              key: 'keycloak-clients',
              property: 'ARGOCD_SESSION_TOKEN',
              metadataPolicy: ExternalSecretSpecDataRemoteRefMetadataPolicy.NONE,
              decodingStrategy: ExternalSecretSpecDataRemoteRefDecodingStrategy.NONE,
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          },
          {
            secretKey: 'BACKSTAGE_CLIENT_SECRET',
            remoteRef: {
              key: 'keycloak-clients',
              property: 'BACKSTAGE_CLIENT_SECRET',
              metadataPolicy: ExternalSecretSpecDataRemoteRefMetadataPolicy.NONE,
              decodingStrategy: ExternalSecretSpecDataRemoteRefDecodingStrategy.NONE,
              conversionStrategy: ExternalSecretSpecDataRemoteRefConversionStrategy.DEFAULT
            }
          }
        ],
        dataFrom: [
          {
            sourceRef: {
              generatorRef: {
                apiVersion: 'generators.external-secrets.io/v1alpha1',
                kind: ExternalSecretSpecDataFromSourceRefGeneratorRefKind.PASSWORD,
                name: 'backstage-session'
              }
            },
            rewrite: [
              {
                transform: {
                  template: 'SESSION_SECRET'
                }
              }
            ]
          }
        ]
      }
    });
  }
}
