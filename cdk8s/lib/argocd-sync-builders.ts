/**
 * Small parity-safe builders for Argo CD sync policies used in applications.ts
 * They return plain objects shaped exactly like the config expects.
 */

export interface SyncRetryBackoff {
  duration?: string;
  factor?: number;
  maxDuration?: string;
}

export interface SyncRetry {
  limit?: number;
  backoff?: SyncRetryBackoff;
}

export interface SyncPolicyShape {
  automated?: {
    prune?: boolean;
    selfHeal?: boolean;
    allowEmpty?: boolean;
  };
  syncOptions?: string[];
  retry?: SyncRetry;
}

export function automatedSyncWithOptions(options: string[], retry?: SyncRetry): SyncPolicyShape {
  return {
    automated: { prune: true, selfHeal: true },
    syncOptions: options,
    ...(retry ? { retry } : {}),
  };
}

/**
 * Standard ignoreDifferences configuration for ExternalSecret resources.
 * Server-side apply causes perpetual OutOfSync due to controller-added fields.
 */
export const EXTERNAL_SECRET_IGNORE_DIFFERENCES = [
  {
    group: 'external-secrets.io',
    kind: 'ExternalSecret',
    jsonPointers: ['/spec/refreshInterval']
  },
  {
    group: 'external-secrets.io',
    kind: 'ClusterSecretStore',
    jsonPointers: ['/spec']
  }
];

/**
 * Standard retry configuration for ESO-dependent apps.
 * Handles webhook not being ready during cluster startup.
 */
export const ESO_RETRY_CONFIG: SyncRetry = {
  limit: 10,
  backoff: {
    duration: '5s',
    factor: 2,
    maxDuration: '3m'
  }
};

/**
 * Build sync policy for apps that depend on External Secrets Operator.
 * Includes retry logic and RespectIgnoreDifferences option.
 */
export function externalSecretsAppSyncPolicy(extraOptions: string[] = []): SyncPolicyShape {
  return automatedSyncWithOptions(
    ['CreateNamespace=true', 'ServerSideApply=true', 'RespectIgnoreDifferences=true', ...extraOptions],
    ESO_RETRY_CONFIG
  );
}

