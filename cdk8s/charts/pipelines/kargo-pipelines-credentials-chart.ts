import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';
import { 
  ExternalSecret,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetDeletionPolicy,
  ExternalSecretSpecTargetTemplateEngineVersion,
  ExternalSecretSpecTargetTemplateMergePolicy,
} from '../../imports/external-secrets.io';
import { createEnvExternalSecret } from '../../lib/eso-helpers';
import { JsonPatch } from 'cdk8s';

/**
 * Kargo Pipelines Credentials Chart
 * Creates image registry credentials for Kargo warehouses in the kargo-pipelines namespace
 */
export class KargoPipelinesCredentialsChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const namespace = 'kargo-pipelines';

    // Create ExternalSecret for GHCR NextJS (chat) credentials
    const ghcrChat = createEnvExternalSecret(this, 'kargo-ghcr-chat-credentials-external', {
      externalName: 'kargo-ghcr-chat-credentials-external',
      name: 'kargo-ghcr-chat-credentials',
      namespace,
      refreshInterval: '1h',
      secretStoreRef: { name: 'azure-keyvault-store', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      deletionPolicy: ExternalSecretSpecTargetDeletionPolicy.RETAIN,
      engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
      mergePolicy: ExternalSecretSpecTargetTemplateMergePolicy.REPLACE,
      templateMetadata: {
        labels: {
          'app.kubernetes.io/name': 'kargo-ghcr-chat-credentials',
          'app.kubernetes.io/part-of': 'kargo-pipelines',
          'kargo.akuity.io/cred-type': 'image'
        }
      },
      templateData: {
        username: 'pittampalliorg',
        password: '{{ .pat }}',
        repoURL: 'ghcr.io/pittampalliorg/chat'
      },
      mappings: [ { key: 'pat', remote: 'GITHUB-PAT' } ],
    });
    ghcrChat.addJsonPatch(JsonPatch.add('/metadata/labels', {
      'app.kubernetes.io/name': 'kargo-ghcr-chat-credentials',
      'app.kubernetes.io/part-of': 'kargo-pipelines',
      'app.kubernetes.io/component': 'credentials'
    }));
    ghcrChat.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-15' }));

    // Create ExternalSecret for GHCR Backstage credentials
    const ghcrBackstage = createEnvExternalSecret(this, 'kargo-ghcr-backstage-credentials-external', {
      externalName: 'kargo-ghcr-backstage-credentials-external',
      name: 'kargo-ghcr-backstage-credentials',
      namespace,
      refreshInterval: '1h',
      secretStoreRef: { name: 'azure-keyvault-store', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      deletionPolicy: ExternalSecretSpecTargetDeletionPolicy.RETAIN,
      engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
      mergePolicy: ExternalSecretSpecTargetTemplateMergePolicy.REPLACE,
      templateMetadata: {
        labels: {
          'app.kubernetes.io/name': 'kargo-ghcr-backstage-credentials',
          'app.kubernetes.io/part-of': 'kargo-pipelines',
          'kargo.akuity.io/cred-type': 'image'
        }
      },
      templateData: {
        username: 'pittampalliorg',
        password: '{{ .pat }}',
        repoURL: 'ghcr.io/pittampalliorg/backstage-cnoe'
      },
      mappings: [ { key: 'pat', remote: 'GITHUB-PAT' } ],
    });
    ghcrBackstage.addJsonPatch(JsonPatch.add('/metadata/labels', {
      'app.kubernetes.io/name': 'kargo-ghcr-backstage-credentials',
      'app.kubernetes.io/part-of': 'kargo-pipelines',
      'app.kubernetes.io/component': 'credentials'
    }));
    ghcrBackstage.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-15' }));

    // Create Git credentials for Kargo to clone GitHub stacks repository
    const gitCreds = createEnvExternalSecret(this, 'kargo-git-credentials-external', {
      externalName: 'kargo-git-credentials-external',
      name: 'kargo-git-credentials',
      namespace,
      refreshInterval: '1h',
      secretStoreRef: { name: 'azure-keyvault-store', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      deletionPolicy: ExternalSecretSpecTargetDeletionPolicy.RETAIN,
      engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
      mergePolicy: ExternalSecretSpecTargetTemplateMergePolicy.REPLACE,
      templateType: 'Opaque',
      templateMetadata: {
        labels: {
          'app.kubernetes.io/name': 'kargo-git-credentials',
          'app.kubernetes.io/part-of': 'kargo-pipelines',
          'kargo.akuity.io/cred-type': 'git'
        }
      },
      templateData: {
        repoURL: 'https://github.com/PittampalliOrg/stacks.git',
        username: 'x-access-token',
        password: '{{ .pat }}',
        type: 'git'
      },
      mappings: [ { key: 'pat', remote: 'GITHUB-PAT' } ],
    });
    gitCreds.addJsonPatch(JsonPatch.add('/metadata/labels', {
      'app.kubernetes.io/name': 'kargo-git-credentials',
      'app.kubernetes.io/part-of': 'kargo-pipelines',
      'app.kubernetes.io/component': 'credentials'
    }));
    gitCreds.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-15' }));

    // Create Git credentials for Kargo to push to Gitea repositories
    // This uses regex matching to handle all giteaAdmin repositories
    const giteaGitCreds = createEnvExternalSecret(this, 'kargo-gitea-git-credentials-external', {
      externalName: 'kargo-gitea-git-credentials-external',
      name: 'kargo-gitea-git-credentials',
      namespace,
      refreshInterval: '5m',
      secretStoreRef: { name: 'gitea', kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE },
      creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
      deletionPolicy: ExternalSecretSpecTargetDeletionPolicy.RETAIN,
      engineVersion: ExternalSecretSpecTargetTemplateEngineVersion.V2,
      mergePolicy: ExternalSecretSpecTargetTemplateMergePolicy.REPLACE,
      templateType: 'Opaque',
      templateMetadata: {
        labels: {
          'app.kubernetes.io/name': 'kargo-gitea-git-credentials',
          'app.kubernetes.io/part-of': 'kargo-pipelines',
          'kargo.akuity.io/cred-type': 'git'
        }
      },
      templateData: {
        // Use regex to match all giteaAdmin repositories
        repoURL: 'https://gitea.cnoe.localtest.me:8443/giteaAdmin/.*',
        repoURLIsRegex: 'true',
        username: '{{ .username }}',
        password: '{{ .token }}'
      },
      mappings: [
        { key: 'username', remoteRef: { key: 'gitea-credential', property: 'username' } },
        { key: 'token', remoteRef: { key: 'gitea-credential', property: 'token' } },
      ],
    });
    giteaGitCreds.addJsonPatch(JsonPatch.add('/metadata/labels', {
      'app.kubernetes.io/name': 'kargo-gitea-git-credentials',
      'app.kubernetes.io/part-of': 'kargo-pipelines',
      'app.kubernetes.io/component': 'credentials'
    }));
    giteaGitCreds.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': '-15' }));
  }
}
