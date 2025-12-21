import { Construct } from 'constructs';
import { Chart, ChartProps } from 'cdk8s';
import { 
  ExternalSecret, 
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecTargetTemplateEngineVersion,
  ExternalSecretSpecSecretStoreRefKind
} from '../../imports/external-secrets.io';
import { createEnvExternalSecret } from '../../lib/eso-helpers';
import { JsonPatch } from 'cdk8s';

/**
 * Creates External Secrets for Headlamp Keycloak authentication
 * Manages OIDC client credentials for Keycloak integration
 */
export class HeadlampKeycloakSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const namespace = 'headlamp';
    const keycloakUrl = process.env.KEYCLOAK_URL || 'https://cnoe.localtest.me:8443/keycloak';
    const keycloakRealm = process.env.KEYCLOAK_REALM || 'cnoe';

    // Headlamp Keycloak OIDC Authentication Secrets
    const oidc = createEnvExternalSecret(this, 'headlamp-oidc-secrets-external', {
      externalName: 'headlamp-oidc-secrets',
      name: 'headlamp-oidc-secrets',
      namespace,
      refreshInterval: '5m',
      secretStoreRef: { name: 'keycloak', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
      templateType: 'Opaque',
      templateData: {
        'OIDC_CLIENT_ID': '{{ .clientId }}',
        'OIDC_CLIENT_SECRET': '{{ .clientSecret }}',
        'OIDC_ISSUER_URL': `${keycloakUrl}/realms/${keycloakRealm}`,
        'OIDC_SCOPES': 'openid email profile',
        'OIDC_REDIRECT_URL': 'https://headlamp.cnoe.localtest.me:8443/oidc-callback'
      },
      mappings: [
        { key: 'clientId', remoteRef: { key: 'headlamp-client-credentials', property: 'client-id' } },
        { key: 'clientSecret', remoteRef: { key: 'headlamp-client-credentials', property: 'client-secret' } }
      ],
    });
    oidc.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-15' }));
  }
}
