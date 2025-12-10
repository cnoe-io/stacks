/**
 * Sync Wave Constants for Talos Linux Cluster Bootstrap
 * Feature: 102-bootstrap-talos-argocd
 *
 * Defines the ordering of ArgoCD Application sync waves for bootstrap sequencing.
 * Lower numbers are deployed first, ensuring dependencies are ready.
 *
 * Usage:
 *   import { SYNC_WAVES } from './lib/sync-waves';
 *   argocd: { syncWave: SYNC_WAVES.OPERATORS }
 */

/**
 * Sync wave constants for bootstrap ordering
 *
 * Deployment Order:
 *   1. FOUNDATION (-110): CNI, critical infrastructure
 *   2. OPERATORS (-100): External Secrets Operator, Tailscale Operator Helm charts
 *   3. IDENTITY (-94): Workload Identity patches (ServiceAccount annotations)
 *   4. STORES (-92): ClusterSecretStore for Azure Key Vault
 *   5. SECRETS (-85): ExternalSecrets for auth credentials (Tailscale, etc.)
 *   6. ACCESS (-80): Tailscale operator (requires OAuth secret)
 *   7. SERVICES (-60): Tailscale serve pods (k8s-api, argocd)
 *   8. PLATFORM (0): Self-managed platform apps (ArgoCD after bootstrap)
 *   9. APPLICATIONS (10): User workloads
 */
export const SYNC_WAVES = {
  /** Critical infrastructure (CNI, node configuration) */
  FOUNDATION: '-110',

  /** Operators that manage CRDs and controllers */
  OPERATORS: '-100',

  /** Identity configuration (Workload Identity patches) */
  IDENTITY: '-94',

  /** Secret stores (ClusterSecretStore, SecretStore) */
  STORES: '-92',

  /** Secrets synced from external providers */
  SECRETS: '-85',

  /** Access layer (Tailscale operator) */
  ACCESS: '-80',

  /** Services exposed via Tailscale */
  SERVICES: '-60',

  /** Platform applications (ArgoCD self-managed) */
  PLATFORM: '0',

  /** User workloads and applications */
  APPLICATIONS: '10',
} as const;

/**
 * Type for sync wave values
 */
export type SyncWave = typeof SYNC_WAVES[keyof typeof SYNC_WAVES];

/**
 * Get all sync waves in order
 */
export function getSyncWavesInOrder(): string[] {
  return Object.values(SYNC_WAVES).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
}

/**
 * Get sync wave name from value
 */
export function getSyncWaveName(value: string): string | undefined {
  for (const [name, wave] of Object.entries(SYNC_WAVES)) {
    if (wave === value) {
      return name;
    }
  }
  return undefined;
}
