import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { ExternalSecret, ExternalSecretSpecTargetCreationPolicy, ExternalSecretSpecTargetTemplateEngineVersion, ExternalSecretSpecSecretStoreRefKind } from '../../imports/external-secrets.io';
import { createEnvExternalSecret } from '../../lib/eso-helpers';
import { JsonPatch } from 'cdk8s';
import { KubeSecret } from '../../imports/k8s';

export interface KargoSecretsChartProps extends ChartProps {
  namespace?: string;
}

export class KargoSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: KargoSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'kargo';

    // Create External Secret for Kargo admin credentials
    const kargoAdmin = createEnvExternalSecret(this, 'kargo-admin-external-secret', {
      externalName: 'kargo-admin-credentials',
      name: 'kargo-admin-credentials',
      namespace,
      refreshInterval: '1h',
      secretStoreRef: { name: 'azure-keyvault-store', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
      templateType: 'Opaque',
      templateData: {
        passwordHash: '{{ .KARGO_ADMIN_PASSWORD_HASH }}',
        tokenSigningKey: '{{ .KARGO_ADMIN_TOKEN_SIGNING_KEY }}',
      },
      mappings: [
        { key: 'KARGO_ADMIN_PASSWORD_HASH', remote: 'KARGO-ADMIN-PASSWORD-HASH' },
        { key: 'KARGO_ADMIN_TOKEN_SIGNING_KEY', remote: 'KARGO-ADMIN-TOKEN-SIGNING-KEY' },
      ],
    });
    kargoAdmin.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-50' }));

    // Create a ConfigMap with instructions for setting up Kargo secrets
    new KubeSecret(this, 'kargo-setup-instructions', {
      metadata: {
        name: 'kargo-setup-instructions',
        namespace: namespace,
      },
      stringData: {
        'setup-instructions.txt': `Kargo Admin Credentials Setup
=============================

1. Generate a secure password:
   pass=$(openssl rand -base64 48 | tr -d "=+/" | head -c 32)
   echo "Password: $pass"

2. Generate the password hash:
   echo "Password Hash: $(htpasswd -bnBC 10 "" $pass | tr -d ':\\n')"

3. Generate a token signing key:
   echo "Signing Key: $(openssl rand -base64 48 | tr -d "=+/" | head -c 32)"

4. Add these values to Azure Key Vault:
   - KARGO-ADMIN-PASSWORD-HASH: <the password hash from step 2>
   - KARGO-ADMIN-TOKEN-SIGNING-KEY: <the signing key from step 3>

5. The External Secret will automatically sync these values to Kubernetes

Note: Keep the plain password from step 1 secure - you'll need it to log into Kargo.
The admin username is: admin
`,
      }
    });
  }
}
