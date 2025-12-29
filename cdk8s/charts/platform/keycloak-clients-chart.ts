/**
 * KeycloakClientsChart - Declarative OIDC Client Configuration
 *
 * This chart creates a ConfigMap with Keycloak realm import JSON containing
 * all OIDC clients. The realm is imported at Keycloak startup via --import-realm.
 *
 * Clients included:
 * - argo-workflows: Argo Workflows SSO
 * - backstage: Backstage developer portal SSO
 * - flipt: Feature flag management UI SSO
 *
 * The approach:
 * 1. Pre-define client secrets in Azure Key Vault
 * 2. ExternalSecret syncs secrets to keycloak-clients-config secret
 * 3. Keycloak deployment mounts the realm JSON and imports on startup
 * 4. Realm import is idempotent - existing realm is skipped
 *
 * Constitution Alignment:
 * - Principle I (CDK8s Typed Composition): Uses typed k8s imports
 * - Principle V (External Secrets Management): Uses ESO for client secrets
 */

import { Construct } from 'constructs';
import { Chart, ChartProps } from 'cdk8s';
import * as k8s from '../../imports/k8s';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

/**
 * Host configuration for generating redirect URIs
 */
export interface HostConfig {
  /** Hostname (e.g., 'cnoe.localtest.me' or 'ai401kchat.com') */
  hostname: string;
  /** Port number (default: 443, use 8443 for KIND clusters) */
  port?: number;
  /** Path prefix for Backstage (default: '/backstage' for path-based routing) */
  backstagePath?: string;
}

export interface KeycloakClientsChartProps extends ChartProps {
  /**
   * Namespace for Keycloak (default: keycloak)
   */
  namespace?: string;

  /**
   * Array of host configurations for generating redirect URIs.
   * Supports multiple environments (dev, staging, prod, etc.)
   */
  hosts?: HostConfig[];

  /**
   * Sync wave for ArgoCD ordering (default: '-80')
   * Should be before keycloak deployment but after secrets
   */
  syncWave?: string;
}

/**
 * KeycloakClientsChart - Declarative Keycloak client configuration
 *
 * Creates resources:
 * 1. ConfigMap: keycloak-realm-import (realm JSON with all clients)
 *
 * Note: Client secrets are referenced from environment variables
 * which are populated by ExternalSecrets from Azure Key Vault.
 */
export class KeycloakClientsChart extends Chart {
  constructor(scope: Construct, id: string, props: KeycloakClientsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace ?? 'keycloak';
    const syncWave = props.syncWave ?? '-80';

    // Build hosts configuration
    const hosts: HostConfig[] = props.hosts ?? [
      {
        hostname: 'cnoe.localtest.me',
        port: 8443,
        backstagePath: '/backstage',
      }
    ];

    // Helper to build base URL from host config
    const buildBaseUrl = (host: HostConfig): string => {
      const port = host.port ?? 443;
      return port === 443 ? `https://${host.hostname}` : `https://${host.hostname}:${port}`;
    };

    // Generate redirect URIs for each client
    const generateBackstageRedirectUris = (): string[] => {
      const uris: string[] = [];
      for (const host of hosts) {
        const baseUrl = buildBaseUrl(host);
        const backstagePath = host.backstagePath ?? '/backstage';
        uris.push(`${baseUrl}/api/auth/keycloak-oidc/handler/frame`);
        if (backstagePath && backstagePath !== '') {
          uris.push(`${baseUrl}${backstagePath}/api/auth/keycloak-oidc/handler/frame`);
        }
      }
      uris.push('http://localhost:7007/api/auth/keycloak-oidc/handler/frame');
      return [...new Set(uris)];
    };

    const generateArgoRedirectUris = (): string[] => {
      const uris: string[] = [];
      for (const host of hosts) {
        const baseUrl = buildBaseUrl(host);
        uris.push(`${baseUrl}/argo-workflows/oauth2/callback`);
      }
      return [...new Set(uris)];
    };

    const generateFliptRedirectUris = (): string[] => {
      const uris: string[] = [];
      for (const host of hosts) {
        const baseUrl = buildBaseUrl(host);
        uris.push(`${baseUrl}/flipt/auth/v1/method/oidc/keycloak/callback`);
      }
      // Internal cluster access
      uris.push('http://flipt.feature-flags.svc.cluster.local:8080/auth/v1/method/oidc/keycloak/callback');
      return [...new Set(uris)];
    };

    // Keycloak realm import JSON
    // Client secrets use placeholder syntax that will be replaced by init container
    const realmJson = {
      realm: 'cnoe',
      enabled: true,
      sslRequired: 'external',
      registrationAllowed: false,
      loginWithEmailAllowed: true,
      duplicateEmailsAllowed: false,
      resetPasswordAllowed: false,
      editUsernameAllowed: false,
      bruteForceProtected: true,

      // Default groups
      groups: [
        { name: 'admin' },
        { name: 'base-user' },
        { name: 'developers' },
        { name: 'platform-team' },
      ],

      // Client scopes
      clientScopes: [
        {
          name: 'groups',
          description: 'Groups a user belongs to',
          protocol: 'openid-connect',
          attributes: {
            'consent.screen.text': 'Access to groups a user belongs to.',
            'display.on.consent.screen': 'true',
            'include.in.token.scope': 'true',
          },
          protocolMappers: [
            {
              name: 'groups',
              protocol: 'openid-connect',
              protocolMapper: 'oidc-group-membership-mapper',
              config: {
                'claim.name': 'groups',
                'full.path': 'false',
                'id.token.claim': 'true',
                'access.token.claim': 'true',
                'userinfo.token.claim': 'true',
              },
            },
          ],
        },
      ],

      // Default client scope mappings
      defaultDefaultClientScopes: [
        'role_list',
        'profile',
        'email',
        'roles',
        'web-origins',
        'acr',
        'groups',
      ],

      // Users - passwords are substituted from USER_PASSWORD env var via envsubst
      users: [
        {
          username: 'user1',
          enabled: true,
          firstName: 'user',
          lastName: 'one',
          groups: ['/admin', '/platform-team'],
          credentials: [
            {
              type: 'password',
              value: '$USER_PASSWORD',
              temporary: false,
            },
          ],
        },
        {
          username: 'user2',
          enabled: true,
          firstName: 'user',
          lastName: 'two',
          groups: ['/base-user', '/developers'],
          credentials: [
            {
              type: 'password',
              value: '$USER_PASSWORD',
              temporary: false,
            },
          ],
        },
      ],

      // OIDC Clients - secrets are substituted from env vars via envsubst
      clients: [
        // Argo Workflows Client
        {
          clientId: 'argo-workflows',
          name: 'Argo Workflows',
          description: 'Argo Workflows SSO integration',
          enabled: true,
          clientAuthenticatorType: 'client-secret',
          secret: '$ARGO_WORKFLOWS_CLIENT_SECRET',
          redirectUris: generateArgoRedirectUris(),
          webOrigins: ['/*'],
          publicClient: false,
          protocol: 'openid-connect',
          standardFlowEnabled: true,
          implicitFlowEnabled: false,
          directAccessGrantsEnabled: true,
          serviceAccountsEnabled: false,
          frontchannelLogout: true,
          defaultClientScopes: ['web-origins', 'profile', 'email', 'roles', 'groups'],
        },

        // Backstage Client
        {
          clientId: 'backstage',
          name: 'Backstage Developer Portal',
          description: 'Backstage SSO integration',
          enabled: true,
          clientAuthenticatorType: 'client-secret',
          secret: '$BACKSTAGE_CLIENT_SECRET',
          redirectUris: generateBackstageRedirectUris(),
          webOrigins: ['/*'],
          publicClient: false,
          protocol: 'openid-connect',
          standardFlowEnabled: true,
          implicitFlowEnabled: false,
          directAccessGrantsEnabled: true,
          serviceAccountsEnabled: false,
          frontchannelLogout: true,
          defaultClientScopes: ['web-origins', 'profile', 'email', 'roles', 'groups'],
        },

        // Flipt Client
        {
          clientId: 'flipt',
          name: 'Flipt Feature Flag Management',
          description: 'Flipt SSO integration for feature flag UI',
          enabled: true,
          clientAuthenticatorType: 'client-secret',
          secret: '$FLIPT_CLIENT_SECRET',
          redirectUris: generateFliptRedirectUris(),
          webOrigins: ['/*'],
          publicClient: false,
          protocol: 'openid-connect',
          standardFlowEnabled: true,
          implicitFlowEnabled: false,
          directAccessGrantsEnabled: true,
          serviceAccountsEnabled: false,
          frontchannelLogout: true,
          defaultClientScopes: ['web-origins', 'profile', 'email', 'roles', 'groups'],
        },
      ],
    };

    // ConfigMap with realm import JSON
    new k8s.KubeConfigMap(this, 'realm-import', {
      metadata: {
        name: 'keycloak-realm-import',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'keycloak',
          'app.kubernetes.io/component': 'realm-config',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      data: {
        'cnoe-realm.json': JSON.stringify(realmJson, null, 2),
      },
    });

    // ConfigMap with instructions for manual setup if needed
    new k8s.KubeConfigMap(this, 'client-setup-instructions', {
      metadata: {
        name: 'keycloak-client-setup',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'keycloak',
          'app.kubernetes.io/component': 'documentation',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      data: {
        'README.md': `# Keycloak Client Configuration

## Declarative Realm Import

The realm configuration is stored in the \`keycloak-realm-import\` ConfigMap.
It contains all OIDC clients with their redirect URIs and settings.

## Clients Configured

| Client ID | Description | Redirect URIs |
|-----------|-------------|---------------|
| argo-workflows | Argo Workflows SSO | /argo-workflows/oauth2/callback |
| backstage | Backstage Developer Portal | /api/auth/keycloak-oidc/handler/frame |
| flipt | Feature Flag Management | /flipt/auth/v1/method/oidc/keycloak/callback |

## Client Secrets

Client secrets are managed via External Secrets and synced from Azure Key Vault:
- ARGO_WORKFLOWS_CLIENT_SECRET
- BACKSTAGE_CLIENT_SECRET
- FLIPT_CLIENT_SECRET

## Updating Configuration

1. Modify the KeycloakClientsChart in cdk8s
2. Run \`npm run synth\`
3. Deploy via ArgoCD
4. Restart Keycloak to pick up changes (if needed)

## Manual Import

If automatic import fails, you can manually import:

\`\`\`bash
kubectl exec -it deploy/keycloak -n keycloak -- \\
  /opt/keycloak/bin/kc.sh import --file /opt/keycloak/data/import/cnoe-realm.json
\`\`\`

## Generating New Client Secrets

To generate new client secrets and store in Azure Key Vault:

\`\`\`bash
# Generate random secrets
ARGO_SECRET=$(openssl rand -base64 32)
BACKSTAGE_SECRET=$(openssl rand -base64 32)
FLIPT_SECRET=$(openssl rand -base64 32)

# Store in Azure Key Vault
az keyvault secret set --vault-name <vault> --name ARGO-WORKFLOWS-CLIENT-SECRET --value "$ARGO_SECRET"
az keyvault secret set --vault-name <vault> --name BACKSTAGE-CLIENT-SECRET --value "$BACKSTAGE_SECRET"
az keyvault secret set --vault-name <vault> --name FLIPT-CLIENT-SECRET --value "$FLIPT_SECRET"
\`\`\`
`,
      },
    });

    // ExternalSecret: Pull client secrets from Azure Key Vault
    // These secrets are used by the init container to substitute into the realm JSON
    new ExternalSecret(this, 'client-secrets', {
      metadata: {
        name: 'keycloak-client-secrets',
        namespace,
        labels: {
          'app.kubernetes.io/name': 'keycloak',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-90', // Before realm import ConfigMap
        },
      },
      spec: {
        refreshInterval: '1h',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'keycloak-client-secrets',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'keycloak',
                'app.kubernetes.io/component': 'secrets',
              },
            },
            data: {
              // Client secrets for realm import (used by envsubst)
              'ARGO_WORKFLOWS_CLIENT_SECRET': '{{ .argoWorkflowsSecret }}',
              'BACKSTAGE_CLIENT_SECRET': '{{ .backstageSecret }}',
              'FLIPT_CLIENT_SECRET': '{{ .fliptSecret }}',
              // User password for realm import
              'USER_PASSWORD': '{{ .userPassword }}',
            },
          },
        },
        data: [
          {
            secretKey: 'argoWorkflowsSecret',
            remoteRef: {
              key: 'ARGO-WORKFLOWS-CLIENT-SECRET',
            },
          },
          {
            secretKey: 'backstageSecret',
            remoteRef: {
              key: 'BACKSTAGE-CLIENT-SECRET',
            },
          },
          {
            secretKey: 'fliptSecret',
            remoteRef: {
              key: 'FLIPT-CLIENT-SECRET',
            },
          },
          {
            secretKey: 'userPassword',
            remoteRef: {
              key: 'KEYCLOAK-USER-PASSWORD',
            },
          },
        ],
      },
    });
  }
}
