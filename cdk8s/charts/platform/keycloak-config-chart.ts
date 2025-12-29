/**
 * KeycloakConfigChart - OIDC Configuration for Keycloak
 *
 * This chart creates the Keycloak configuration Job that sets up:
 * - CNOE realm
 * - Groups (admin, base-user)
 * - Users (user1, user2)
 * - OIDC clients (argo-workflows, backstage)
 * - keycloak-clients secret with client credentials
 *
 * Based on ref-implementation/keycloak/manifests/keycloak-config.yaml
 *
 * Constitution Alignment:
 * - Principle I (CDK8s Typed Composition): Uses typed k8s imports
 */

import { Construct } from 'constructs';
import { Chart, ChartProps } from 'cdk8s';
import * as k8s from '../../imports/k8s';

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

export interface KeycloakConfigChartProps extends ChartProps {
  /**
   * Namespace for Keycloak config (default: keycloak)
   */
  namespace?: string;

  /**
   * Base hostname for redirect URIs (default: cnoe.localtest.me)
   * @deprecated Use `hosts` array instead for multi-environment support
   */
  hostname?: string;

  /**
   * Port for redirect URIs (default: 8443)
   * @deprecated Use `hosts` array instead for multi-environment support
   */
  hostnamePort?: number;

  /**
   * Array of host configurations for generating redirect URIs.
   * Supports multiple Backstage environments (dev, staging, prod, etc.)
   * Each host generates redirect URIs for both root and path-based routing.
   *
   * Example:
   * ```typescript
   * hosts: [
   *   { hostname: 'cnoe.localtest.me', port: 8443, backstagePath: '/backstage' },
   *   { hostname: 'ai401kchat.com', port: 443, backstagePath: '/backstage' },
   *   { hostname: 'dev.example.com', port: 443, backstagePath: '' },  // Domain-based routing
   * ]
   * ```
   */
  hosts?: HostConfig[];
}

/**
 * KeycloakConfigChart - OIDC configuration Job for Keycloak
 *
 * Creates resources:
 * 1. ServiceAccount: keycloak-config
 * 2. Role: keycloak-config (keycloak namespace - secrets)
 * 3. RoleBinding: keycloak-config (keycloak namespace)
 * 4. Role: keycloak-config (argocd namespace - secrets)
 * 5. RoleBinding: keycloak-config (argocd namespace)
 * 6. ConfigMap: config-job (OIDC client payloads)
 * 7. Job: config (PostSync hook - creates realm, users, clients)
 */
export class KeycloakConfigChart extends Chart {
  constructor(scope: Construct, id: string, props: KeycloakConfigChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace ?? 'keycloak';

    // Build hosts configuration from either new hosts array or legacy props
    const hosts: HostConfig[] = props.hosts ?? [
      {
        hostname: props.hostname ?? 'cnoe.localtest.me',
        port: props.hostnamePort ?? 8443,
        backstagePath: '/backstage',  // Default to path-based routing
      }
    ];

    // Helper to build base URL from host config
    const buildBaseUrl = (host: HostConfig): string => {
      const port = host.port ?? 443;
      return port === 443 ? `https://${host.hostname}` : `https://${host.hostname}:${port}`;
    };

    // Generate all redirect URIs for Backstage across all configured hosts
    const generateBackstageRedirectUris = (): string[] => {
      const uris: string[] = [];
      for (const host of hosts) {
        const baseUrl = buildBaseUrl(host);
        const backstagePath = host.backstagePath ?? '/backstage';

        // Always include the root API path (for domain-based routing)
        uris.push(`${baseUrl}/api/auth/keycloak-oidc/handler/frame`);

        // Include path-prefixed URI if backstagePath is set
        if (backstagePath && backstagePath !== '') {
          uris.push(`${baseUrl}${backstagePath}/api/auth/keycloak-oidc/handler/frame`);
        }
      }
      // Always include localhost for development
      uris.push('http://localhost:7007/api/auth/keycloak-oidc/handler/frame');
      // Deduplicate
      return [...new Set(uris)];
    };

    // Generate all redirect URIs for Argo Workflows across all configured hosts
    const generateArgoRedirectUris = (): string[] => {
      const uris: string[] = [];
      for (const host of hosts) {
        const baseUrl = buildBaseUrl(host);
        uris.push(`${baseUrl}/argo-workflows/oauth2/callback`);
      }
      return [...new Set(uris)];
    };

    // Generate all redirect URIs for Flipt across all configured hosts
    const generateFliptRedirectUris = (): string[] => {
      const uris: string[] = [];
      for (const host of hosts) {
        const baseUrl = buildBaseUrl(host);
        // Flipt uses /auth/v1/method/oidc/callback for OIDC callback
        uris.push(`${baseUrl}/flipt/auth/v1/method/oidc/callback`);
        // Also support direct access without path prefix
        uris.push(`http://flipt.feature-flags.svc.cluster.local:8080/auth/v1/method/oidc/callback`);
      }
      return [...new Set(uris)];
    };

    // For backward compatibility, keep baseUrl pointing to first host
    const baseUrl = buildBaseUrl(hosts[0]);

    // ==========================================================================
    // ServiceAccount
    // ==========================================================================

    new k8s.KubeServiceAccount(this, 'keycloak-config-sa', {
      metadata: {
        name: 'keycloak-config',
        namespace,
      },
    });

    // ==========================================================================
    // RBAC - keycloak namespace
    // ==========================================================================

    new k8s.KubeRole(this, 'keycloak-config-role-keycloak', {
      metadata: {
        name: 'keycloak-config-secrets',  // Unique name for keycloak namespace
        namespace,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'create', 'update', 'patch'],
        },
      ],
    });

    new k8s.KubeRoleBinding(this, 'keycloak-config-rolebinding-keycloak', {
      metadata: {
        name: 'keycloak-config-secrets',  // Unique name for keycloak namespace
        namespace,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'keycloak-config',
          namespace,
        },
      ],
      roleRef: {
        kind: 'Role',
        name: 'keycloak-config-secrets',  // Match the role name
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // ==========================================================================
    // RBAC - argocd namespace (for reading ArgoCD admin secret)
    // ==========================================================================

    new k8s.KubeRole(this, 'keycloak-config-role-argocd', {
      metadata: {
        name: 'keycloak-config-argocd',  // Unique name for argocd namespace
        namespace: 'argocd',
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get'],
        },
      ],
    });

    new k8s.KubeRoleBinding(this, 'keycloak-config-rolebinding-argocd', {
      metadata: {
        name: 'keycloak-config-argocd',  // Unique name for argocd namespace
        namespace: 'argocd',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'keycloak-config',
          namespace,
        },
      ],
      roleRef: {
        kind: 'Role',
        name: 'keycloak-config-argocd',  // Match the role name
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // ==========================================================================
    // ConfigMap: config-job (OIDC payloads)
    // ==========================================================================

    new k8s.KubeConfigMap(this, 'config-job-cm', {
      metadata: {
        name: 'config-job',
        namespace,
      },
      data: {
        'client-scope-groups-payload.json': JSON.stringify({
          name: 'groups',
          description: 'groups a user belongs to',
          attributes: {
            'consent.screen.text': 'Access to groups a user belongs to.',
            'display.on.consent.screen': 'true',
            'include.in.token.scope': 'true',
            'gui.order': '',
          },
          type: 'default',
          protocol: 'openid-connect',
        }),
        'group-admin-payload.json': JSON.stringify({ name: 'admin' }),
        'group-base-user-payload.json': JSON.stringify({ name: 'base-user' }),
        'group-mapper-payload.json': JSON.stringify({
          protocol: 'openid-connect',
          protocolMapper: 'oidc-group-membership-mapper',
          name: 'groups',
          config: {
            'claim.name': 'groups',
            'full.path': 'false',
            'id.token.claim': 'true',
            'access.token.claim': 'true',
            'userinfo.token.claim': 'true',
          },
        }),
        'realm-payload.json': JSON.stringify({ realm: 'cnoe', enabled: true }),
        'user-password.json': JSON.stringify({
          temporary: false,
          type: 'password',
          value: '${USER1_PASSWORD}',
        }),
        'user-user1.json': JSON.stringify({
          username: 'user1',
          email: '',
          firstName: 'user',
          lastName: 'one',
          requiredActions: [],
          emailVerified: false,
          groups: ['/admin'],
          enabled: true,
        }),
        'user-user2.json': JSON.stringify({
          username: 'user2',
          email: '',
          firstName: 'user',
          lastName: 'two',
          requiredActions: [],
          emailVerified: false,
          groups: ['/base-user'],
          enabled: true,
        }),
        'argo-client-payload.json': JSON.stringify({
          protocol: 'openid-connect',
          clientId: 'argo-workflows',
          name: 'Argo Workflows Client',
          description: 'Used for Argo Workflows SSO',
          publicClient: false,
          authorizationServicesEnabled: false,
          serviceAccountsEnabled: false,
          implicitFlowEnabled: false,
          directAccessGrantsEnabled: true,
          standardFlowEnabled: true,
          frontchannelLogout: true,
          attributes: {
            saml_idp_initiated_sso_url_name: '',
            'oauth2.device.authorization.grant.enabled': false,
            'oidc.ciba.grant.enabled': false,
          },
          alwaysDisplayInConsole: false,
          rootUrl: '',
          baseUrl: '',
          redirectUris: generateArgoRedirectUris(),
          webOrigins: ['/*'],
        }),
        'backstage-client-payload.json': JSON.stringify({
          protocol: 'openid-connect',
          clientId: 'backstage',
          name: 'Backstage Client',
          description: 'Used for Backstage SSO',
          publicClient: false,
          authorizationServicesEnabled: false,
          serviceAccountsEnabled: false,
          implicitFlowEnabled: false,
          directAccessGrantsEnabled: true,
          standardFlowEnabled: true,
          frontchannelLogout: true,
          attributes: {
            saml_idp_initiated_sso_url_name: '',
            'oauth2.device.authorization.grant.enabled': false,
            'oidc.ciba.grant.enabled': false,
          },
          alwaysDisplayInConsole: false,
          rootUrl: '',
          baseUrl: '',
          redirectUris: generateBackstageRedirectUris(),
          webOrigins: ['/*'],
        }),
        'flipt-client-payload.json': JSON.stringify({
          protocol: 'openid-connect',
          clientId: 'flipt',
          name: 'Flipt Feature Flag Management',
          description: 'Used for Flipt Feature Flag UI SSO',
          publicClient: false,
          authorizationServicesEnabled: false,
          serviceAccountsEnabled: false,
          implicitFlowEnabled: false,
          directAccessGrantsEnabled: true,
          standardFlowEnabled: true,
          frontchannelLogout: true,
          attributes: {
            saml_idp_initiated_sso_url_name: '',
            'oauth2.device.authorization.grant.enabled': false,
            'oidc.ciba.grant.enabled': false,
          },
          alwaysDisplayInConsole: false,
          rootUrl: '',
          baseUrl: '',
          redirectUris: generateFliptRedirectUris(),
          webOrigins: ['/*'],
        }),
      },
    });

    // ==========================================================================
    // Job: config (PostSync hook - runs after keycloak is deployed and ready)
    // PostSync ensures keycloak pods are running before the Job tries to configure.
    // Note: backstage-secrets uses refreshInterval: 1m to retry until this completes.
    // ==========================================================================

    new k8s.KubeJob(this, 'config-job', {
      metadata: {
        name: 'config',
        namespace,
        annotations: {
          'argocd.argoproj.io/hook': 'PostSync',
          // Allow ArgoCD to safely re-run this hook on updates without leaving
          // stale Jobs stuck in a Terminating state.
          'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
        },
      },
      spec: {
        // Prevent a stuck hook from blocking ArgoCD indefinitely.
        // 15 min timeout allows for keycloak startup + image pulls
        activeDeadlineSeconds: 900,
        // Retry up to 10 times to handle keycloak startup delays
        backoffLimit: 10,
        template: {
          metadata: {
            generateName: 'config',
          },
          spec: {
            serviceAccountName: 'keycloak-config',
            restartPolicy: 'Never',
            volumes: [
              {
                name: 'keycloak-config',
                secret: {
                  secretName: 'keycloak-config',
                },
              },
              {
                name: 'config-payloads',
                configMap: {
                  name: 'config-job',
                },
              },
            ],
            containers: [
              {
                name: 'kubectl',
                image: 'docker.io/library/ubuntu:22.04',
                volumeMounts: [
                  {
                    name: 'keycloak-config',
                    readOnly: true,
                    mountPath: '/var/secrets/',
                  },
                  {
                    name: 'config-payloads',
                    readOnly: true,
                    mountPath: '/var/config/',
                  },
                ],
                command: ['/bin/bash', '-c'],
                args: [
                  `#!/bin/bash
set -ex -o pipefail

apt -qq update && apt -qq install curl jq -y

ADMIN_PASSWORD=$(cat /var/secrets/KEYCLOAK_ADMIN_PASSWORD)
USER1_PASSWORD=$(cat /var/secrets/USER_PASSWORD)

KEYCLOAK_URL=http://keycloak.keycloak.svc.cluster.local:8080/keycloak

KEYCLOAK_TOKEN=$(curl -sS  --fail-with-body -X POST -H "Content-Type: application/x-www-form-urlencoded" \\
  --data-urlencode "username=cnoe-admin" \\
  --data-urlencode "password=\${ADMIN_PASSWORD}" \\
  --data-urlencode "grant_type=password" \\
  --data-urlencode "client_id=admin-cli" \\
  \${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token | jq -e -r '.access_token')

set +e

# Check if realm exists
curl --fail-with-body -H "Authorization: bearer \${KEYCLOAK_TOKEN}"  "\${KEYCLOAK_URL}/admin/realms/cnoe"  &> /dev/null
REALM_EXISTS=$?
set -e

	# Always need kubectl for secret creation
	curl -sS -LO "https://dl.k8s.io/release/v1.28.3//bin/linux/amd64/kubectl"
	chmod +x kubectl

	patch_client_redirects() {
	  local client_name="$1"
	  local payload_file="$2"

	  if [ ! -f "$payload_file" ]; then
	    echo "payload file not found: $payload_file"
	    return 1
	  fi

	  local desired_redirects
	  desired_redirects=$(jq -c '.redirectUris' "$payload_file")

	  local existing_client_id
	  existing_client_id=$(curl -sS -H "Content-Type: application/json" \\
	    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
	    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -r --arg name "$client_name" '.[] | select(.clientId == $name) | .id' | head -1)

	  if [ -z "$existing_client_id" ] || [ "$existing_client_id" = "null" ]; then
	    echo "client '\${client_name}' not found; creating"
	    curl -sS -H "Content-Type: application/json" \\
	      -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
	      -X POST --data @"$payload_file" \\
	      \${KEYCLOAK_URL}/admin/realms/cnoe/clients
	    existing_client_id=$(curl -sS -H "Content-Type: application/json" \\
	      -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
	      -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -r --arg name "$client_name" '.[] | select(.clientId == $name) | .id' | head -1)
	  fi

	  echo "ensuring redirectUris for client '\${client_name}' (\${existing_client_id})"
	  local existing_json updated_json
	  existing_json=$(curl -sS -H "Content-Type: application/json" \\
	    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
	    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${existing_client_id})
	  updated_json=$(echo "$existing_json" | jq --argjson redirects "$desired_redirects" '.redirectUris = $redirects')

	  curl -sS -H "Content-Type: application/json" \\
	    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
	    -X PUT --data "$updated_json" \\
	    \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${existing_client_id} >/dev/null
	}

	# If realm exists, check if keycloak-clients secret exists
	if [ $REALM_EXISTS -eq 0 ]; then
	  # Realm exists: still ensure redirect URIs match the desired payloads
	  patch_client_redirects "argo-workflows" "/var/config/argo-client-payload.json"
	  patch_client_redirects "backstage" "/var/config/backstage-client-payload.json"
	  patch_client_redirects "flipt" "/var/config/flipt-client-payload.json"

	  # Check if secret already exists
	  if ./kubectl -n keycloak get secret keycloak-clients &>/dev/null; then
	    echo "Realm and secret already exist; redirect URIs reconciled"
	    exit 0
	  fi
  echo "Realm exists but secret missing, recreating secret..."

  # Get existing client secrets from Keycloak
  KEYCLOAK_TOKEN=$(curl -sS  --fail-with-body -X POST -H "Content-Type: application/x-www-form-urlencoded" \\
    --data-urlencode "username=cnoe-admin" \\
    --data-urlencode "password=\${ADMIN_PASSWORD}" \\
    --data-urlencode "grant_type=password" \\
    --data-urlencode "client_id=admin-cli" \\
    \${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token | jq -e -r '.access_token')

  # Get Argo Workflows client secret
  CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \\
    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "argo-workflows") | .id')
  ARGO_WORKFLOWS_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \\
    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID} | jq -e -r '.secret')

  # Get Backstage client secret
  CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \\
    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "backstage") | .id')
  BACKSTAGE_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \\
    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID} | jq -e -r '.secret')

  # Get Flipt client secret
  CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \\
    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "flipt") | .id')
  FLIPT_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \\
    -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
    -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID} | jq -e -r '.secret')

  # Get ArgoCD session token
  ARGOCD_PASSWORD=$(./kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode }}')
  ARGOCD_SESSION_TOKEN=$(curl -k -sS http://argocd-server.argocd.svc.cluster.local:443/api/v1/session -H 'Content-Type: application/json' -d "{\\"username\\":\\"admin\\",\\"password\\":\\"\${ARGOCD_PASSWORD}\\"}" | jq -r .token)

  # Create the secret
  echo "
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-clients
  namespace: keycloak
type: Opaque
stringData:
  ARGO_WORKFLOWS_CLIENT_SECRET: \${ARGO_WORKFLOWS_CLIENT_SECRET}
  ARGO_WORKFLOWS_CLIENT_ID: argo-workflows
  ARGOCD_SESSION_TOKEN: \${ARGOCD_SESSION_TOKEN}
  BACKSTAGE_CLIENT_SECRET: \${BACKSTAGE_CLIENT_SECRET}
  BACKSTAGE_CLIENT_ID: backstage
  FLIPT_CLIENT_SECRET: \${FLIPT_CLIENT_SECRET}
  FLIPT_CLIENT_ID: flipt
" > /tmp/secret.yaml

  ./kubectl apply -f /tmp/secret.yaml
  exit 0
fi

echo "creating cnoe realm and groups"

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/realm-payload.json \\
  \${KEYCLOAK_URL}/admin/realms

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/client-scope-groups-payload.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/group-admin-payload.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/groups

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/group-base-user-payload.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/groups

# Create scope mapper
echo 'adding group claim to tokens'
CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" -H "Authorization: bearer \${KEYCLOAK_TOKEN}" -X GET  \${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/group-mapper-payload.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes/\${CLIENT_SCOPE_GROUPS_ID}/protocol-mappers/models

echo "creating test users"
curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/user-user1.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/users

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/user-user2.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/users

USER1ID=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" "\${KEYCLOAK_URL}/admin/realms/cnoe/users?lastName=one" | jq -r '.[0].id')
USER2ID=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" "\${KEYCLOAK_URL}/admin/realms/cnoe/users?lastName=two" | jq -r '.[0].id')

echo "setting user passwords"
jq -r --arg pass \${USER1_PASSWORD}  '.value = $pass' /var/config/user-password.json > /tmp/user-password-to-be-applied.json

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X PUT --data @/tmp/user-password-to-be-applied.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/users/\${USER1ID}/reset-password

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X PUT --data @/tmp/user-password-to-be-applied.json \\
  \${KEYCLOAK_URL}/admin/realms/cnoe/users/\${USER2ID}/reset-password

echo "creating Argo Workflows client"
curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
    -X POST --data @/var/config/argo-client-payload.json \\
    \${KEYCLOAK_URL}/admin/realms/cnoe/clients

CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "argo-workflows") | .id')
CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X GET  \${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')

curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X PUT  \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID}/default-client-scopes/\${CLIENT_SCOPE_GROUPS_ID}

ARGO_WORKFLOWS_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \\
-H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
-X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID} | jq -e -r '.secret')

echo "creating Backstage client"
curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/backstage-client-payload.json \\
    \${KEYCLOAK_URL}/admin/realms/cnoe/clients

CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "backstage") | .id')

CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" -H "Authorization: bearer \${KEYCLOAK_TOKEN}" -X GET  \${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')
curl -sS -H "Content-Type: application/json" -H "Authorization: bearer \${KEYCLOAK_TOKEN}" -X PUT  \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID}/default-client-scopes/\${CLIENT_SCOPE_GROUPS_ID}

BACKSTAGE_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID} | jq -e -r '.secret')

echo "creating Flipt client"
curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X POST --data @/var/config/flipt-client-payload.json \\
    \${KEYCLOAK_URL}/admin/realms/cnoe/clients

CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "flipt") | .id')

CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" -H "Authorization: bearer \${KEYCLOAK_TOKEN}" -X GET  \${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')
curl -sS -H "Content-Type: application/json" -H "Authorization: bearer \${KEYCLOAK_TOKEN}" -X PUT  \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID}/default-client-scopes/\${CLIENT_SCOPE_GROUPS_ID}

FLIPT_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \\
  -H "Authorization: bearer \${KEYCLOAK_TOKEN}" \\
  -X GET \${KEYCLOAK_URL}/admin/realms/cnoe/clients/\${CLIENT_ID} | jq -e -r '.secret')

ARGOCD_PASSWORD=$(./kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode }}')

ARGOCD_SESSION_TOKEN=$(curl -k -sS http://argocd-server.argocd.svc.cluster.local:443/api/v1/session -H 'Content-Type: application/json' -d "{\\"username\\":\\"admin\\",\\"password\\":\\"\${ARGOCD_PASSWORD}\\"}" | jq -r .token)

echo "
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-clients
  namespace: keycloak
type: Opaque
stringData:
  ARGO_WORKFLOWS_CLIENT_SECRET: \${ARGO_WORKFLOWS_CLIENT_SECRET}
  ARGO_WORKFLOWS_CLIENT_ID: argo-workflows
  ARGOCD_SESSION_TOKEN: \${ARGOCD_SESSION_TOKEN}
  BACKSTAGE_CLIENT_SECRET: \${BACKSTAGE_CLIENT_SECRET}
  BACKSTAGE_CLIENT_ID: backstage
  FLIPT_CLIENT_SECRET: \${FLIPT_CLIENT_SECRET}
  FLIPT_CLIENT_ID: flipt
" > /tmp/secret.yaml

./kubectl apply -f /tmp/secret.yaml
`,
                ],
              },
            ],
          },
        },
      },
    });
  }
}
