/**
 * Deterministic cluster identity helpers.
 *
 * Used for host-suffixed naming across:
 * - Tailscale Services (svc:<name>-<cluster>)
 * - Local ingress hosts (<service>-<cluster>.<base-domain>)
 *
 * The "cluster" portion is derived from CLUSTER_NAME (preferred) or CLUSTER_HOST.
 */

/**
 * Normalize an arbitrary cluster identifier to something close to a DNS label.
 * - lowercases
 * - replaces non [a-z0-9-] with '-'
 * - trims leading/trailing '-'
 */
export function normalizeClusterId(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-+/, '')
    .replace(/-+$/, '');
}

/**
 * Read the cluster identifier from environment variables.
 *
 * Prefer CLUSTER_NAME (target cluster identifier) and fall back to CLUSTER_HOST
 * (local host name) to keep KIND workflows working.
 */
export function getClusterId(): string {
  const raw = (process.env.CLUSTER_NAME || process.env.CLUSTER_HOST || '').trim();
  return normalizeClusterId(raw);
}

/**
 * Get the normalized cluster suffix used for host-suffixed naming.
 * Includes a leading '-' when present, otherwise ''.
 */
export function getClusterSuffix(): string {
  const clusterId = getClusterId();
  return clusterId ? `-${clusterId}` : '';
}

