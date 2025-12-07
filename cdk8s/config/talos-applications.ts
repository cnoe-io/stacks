/**
 * Application Configuration for Talos Linux Cluster
 * Feature: 102-bootstrap-talos-argocd
 *
 * Defines all applications to be managed by ArgoCD in the Talos cluster.
 * Applications are deployed in sync wave order (lower = earlier).
 *
 * Sync Wave Ordering:
 *   -110: Foundation (CNI, critical infra)
 *   -100: Operators (ESO, Tailscale)
 *    -94: Identity (Workload Identity patches)
 *    -92: Stores (ClusterSecretStore)
 *    -85: Secrets (ExternalSecrets for auth)
 *    -80: Access (Tailscale operator)
 *    -60: Services (Tailscale serve pods)
 *      0: Platform (ArgoCD self-managed)
 *     10: Applications (User workloads)
 */

import { ApplicationConfig } from '../lib/idpbuilder-types';
import { SYNC_WAVES } from '../lib/sync-waves';

// Re-export for backward compatibility
export { SYNC_WAVES } from '../lib/sync-waves';

/**
 * Environment variable helpers with defaults
 */
const env = {
  get: (name: string, defaultValue?: string): string => {
    const value = process.env[name] || defaultValue;
    if (!value) {
      throw new Error(`Required environment variable not set: ${name}`);
    }
    return value;
  },
  getOptional: (name: string, defaultValue: string): string => {
    return process.env[name] || defaultValue;
  },
};

/**
 * Talos cluster application configurations
 * Ordered by sync wave for deployment sequencing
 */
export const talosApplications: ApplicationConfig[] = [
  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -100: Operators
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'external-secrets-operator',
    namespace: 'external-secrets',
    chart: {
      type: 'EsoHelmChart',
      props: {
        version: '0.9.13',
        installCrds: true,
        enableWebhook: true,
        replicaCount: 2,
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.OPERATORS,
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'platform',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -94: Identity (Workload Identity Configuration)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'workload-identity-patch',
    namespace: 'external-secrets',
    chart: {
      type: 'WorkloadIdentityPatchChart',
      props: {
        clientId: env.getOptional('AZURE_CLIENT_ID', ''),
        tenantId: env.getOptional('AZURE_TENANT_ID', ''),
        serviceAccountName: 'external-secrets',
        serviceAccountNamespace: 'external-secrets',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.IDENTITY,
      labels: {
        'app.kubernetes.io/component': 'identity',
        'app.kubernetes.io/part-of': 'platform',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['ServerSideApply=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -92: Secret Stores
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'cluster-secret-store',
    namespace: 'external-secrets',
    chart: {
      type: 'ClusterSecretStoreChart',
      props: {
        storeName: 'azure-keyvault-store',
        keyVaultName: env.getOptional('AZURE_KEYVAULT_NAME', 'talos-keyvault'),
        serviceAccountRef: {
          name: 'external-secrets',
          namespace: 'external-secrets',
        },
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.STORES,
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'platform',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -85: Secrets (ExternalSecrets for Tailscale)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'tailscale-secrets',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleSecretsChart',
      props: {
        secretStoreName: 'azure-keyvault-store',
        authKeySecretName: 'tailscale-auth-key',
        oauthSecretName: 'operator-oauth',
        refreshInterval: '24h',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.SECRETS,
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -80: Access (Tailscale Operator)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'tailscale-operator',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleOperatorChart',
      props: {
        version: '1.76.1',
        hostname: 'talos-operator',
        enableApiServerProxy: true,
        enableHA: false, // Single node for dev
        tags: ['tag:k8s-operator'],
        oauthSecretName: 'operator-oauth',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.ACCESS,
      labels: {
        'app.kubernetes.io/component': 'networking',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -60: Services (Tailscale Serve Pods)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'k8s-api-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'K8sApiTailscaleServeChart',
      props: {
        serviceName: 'k8s-api',
        backendHost: 'kubernetes.default.svc.cluster.local',
        backendPort: 443,
        enableKubectlProxy: true,
        kubectlProxyPort: 8001,
        authKeySecretName: 'tailscale-auth-key',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.SERVICES,
      labels: {
        'app.kubernetes.io/component': 'access',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'argocd-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'ArgoCDTailscaleServeChart',
      props: {
        serviceName: 'argocd',
        backendHost: 'argocd-server.argocd.svc.cluster.local',
        backendPort: 443,
        backendInsecure: true, // ArgoCD uses self-signed cert
        authKeySecretName: 'tailscale-auth-key',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.SERVICES,
      labels: {
        'app.kubernetes.io/component': 'access',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE 0: Platform (ArgoCD Self-Managed - FUTURE)
  // ═══════════════════════════════════════════════════════════════════════════
  // Note: ArgoCD is initially installed via Helm, then can self-manage
  // Add ArgoCD Application for self-management here if needed

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE 10: Applications (User Workloads - Add as needed)
  // ═══════════════════════════════════════════════════════════════════════════
];

/**
 * Get applications by sync wave
 */
export function getApplicationsBySyncWave(wave: string): ApplicationConfig[] {
  return talosApplications.filter((app) => app.argocd?.syncWave === wave);
}

/**
 * Get applications sorted by sync wave (for ordered deployment)
 */
export function getApplicationsSortedBySyncWave(): ApplicationConfig[] {
  return [...talosApplications].sort((a, b) => {
    const waveA = parseInt(a.argocd?.syncWave || '0', 10);
    const waveB = parseInt(b.argocd?.syncWave || '0', 10);
    return waveA - waveB;
  });
}

/**
 * Validate that all required chart types are registered
 */
export function validateChartTypes(registeredTypes: string[]): string[] {
  const requiredTypes = new Set(talosApplications.map((app) => app.chart.type));
  const missingTypes: string[] = [];

  Array.from(requiredTypes).forEach((type) => {
    if (!registeredTypes.includes(type)) {
      missingTypes.push(type);
    }
  });

  return missingTypes;
}
