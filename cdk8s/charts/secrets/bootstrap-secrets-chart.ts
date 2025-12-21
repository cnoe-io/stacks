import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { 
  ExternalSecret,
  ClusterSecretStore,
  ClusterSecretStoreSpecProviderAzurekvAuthType,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecSecretStoreRefKind
} from '../../imports/external-secrets.io';
import { createEnvExternalSecret } from '../../lib/eso-helpers';
import { JsonPatch } from 'cdk8s';
import { ExternalSecretsWorkloadIdentityChart } from './external-secrets-workload-identity-chart';

export interface BootstrapSecretsChartProps extends ChartProps {
  externalSecretsWorkloadIdentity?: ExternalSecretsWorkloadIdentityChart;
}

/**
 * Bootstrap Secrets Chart
 * Manages initial secrets required for ArgoCD to access private repositories
 * This includes the GitHub App credentials for repository access
 */
export class BootstrapSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: BootstrapSecretsChartProps = {}) {
    super(scope, id, props);

    // GitHub App Repository Credentials ExternalSecret
    const ghRepoCreds = createEnvExternalSecret(this, 'github-app-repo-creds-external', {
      externalName: 'github-app-repo-creds-external',
      name: 'github-app-repo-creds-from-external',
      namespace: 'argocd',
      refreshInterval: '10m',
      secretStoreRef: { name: 'azure-keyvault-store', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      templateMetadata: { labels: { 'argocd.argoproj.io/secret-type': 'repository' } },
      templateData: {
        type: 'git',
        url: 'https://github.com/PittampalliOrg/cdk8s-project.git',
        githubAppID: '1272071',
        githubAppInstallationID: '66754705',
        githubAppPrivateKey: '{{ .ghPrivateKey | toString }}',
      },
      mappings: [ { key: 'ghPrivateKey', remote: 'github-app-private-key' } ],
    });
    ghRepoCreds.addJsonPatch(JsonPatch.add('/metadata/labels', { 'app.kubernetes.io/managed-by': 'bootstrap' }));
    ghRepoCreds.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-90' }));

    // Azure KeyVault ClusterSecretStore
    // This is created here as it's required for all other ExternalSecrets
    const clusterSecretStore = new ClusterSecretStore(this, 'azure-keyvault-store', {
      metadata: {
        name: 'azure-keyvault-store',
        labels: {
          'app.kubernetes.io/managed-by': 'bootstrap',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-92',
        },
      },
      spec: {
        provider: {
          azurekv: {
            vaultUrl: `https://${process.env.AZURE_KEYVAULT_NAME}.vault.azure.net`,
            authType: ClusterSecretStoreSpecProviderAzurekvAuthType.WORKLOAD_IDENTITY,
            serviceAccountRef: {
              name: 'external-secrets',
              namespace: 'external-secrets',
            },
          },
        },
      },
    });

    // Add dependency on workload identity if provided
    if (props.externalSecretsWorkloadIdentity) {
      clusterSecretStore.addDependency(props.externalSecretsWorkloadIdentity.serviceAccountPatch);
    }

    // GitHub PEM Key ExternalSecret
    // This is used by various GitHub integrations
    const ghPem = createEnvExternalSecret(this, 'github-pem-external', {
      externalName: 'github-pem',
      name: 'github-pem',
      namespace: 'argocd',
      refreshInterval: '10m',
      secretStoreRef: { name: 'azure-keyvault-store', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      mappings: [ { key: 'privateKey', remote: 'github-app-private-key' } ],
    });
    ghPem.addJsonPatch(JsonPatch.add('/metadata/labels', { 'app.kubernetes.io/managed-by': 'bootstrap' }));
    ghPem.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-90' }));
  }
}
