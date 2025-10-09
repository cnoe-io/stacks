/**
 * KagentSecretsChart - Manages LLM Provider API keys via External Secrets Operator
 *
 * This chart creates ExternalSecret resources that sync LLM provider API keys
 * from Azure Key Vault into Kubernetes secrets for use by kagent agents.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';
import { kagentSyncWave } from '../../lib/kagent-helpers';

export class KagentSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const ns = 'kagent';

    // ExternalSecret for LLM Provider API Keys
    new ExternalSecret(this, 'llm-providers', {
      metadata: {
        name: 'kagent-llm-providers',
        namespace: ns,
        annotations: kagentSyncWave(-70),
      },
      spec: {
        refreshInterval: '1h',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'kagent-llm-providers',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            data: {
              OPENAI_API_KEY: '{{ .openai_api_key | default "" }}',
              ANTHROPIC_API_KEY: '{{ .anthropic_api_key | default "" }}',
              GEMINI_API_KEY: '{{ .gemini_api_key | default "" }}',
            },
          },
        },
        data: [
          {
            secretKey: 'openai_api_key',
            remoteRef: {
              key: 'llm-providers-openai',
              property: 'api_key',
            },
          },
          {
            secretKey: 'anthropic_api_key',
            remoteRef: {
              key: 'llm-providers-anthropic',
              property: 'api_key',
            },
          },
          {
            secretKey: 'gemini_api_key',
            remoteRef: {
              key: 'llm-providers-gemini',
              property: 'api_key',
            },
          },
        ],
      },
    });
  }
}
