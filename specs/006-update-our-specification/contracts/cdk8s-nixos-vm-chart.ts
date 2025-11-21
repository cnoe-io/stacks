/**
 * CDK8s NixOS VM Chart Contract
 * Feature: 006-update-our-specification
 * Purpose: Define TypeScript interface for NixOS VM chart props with RustDesk base image
 */

import { ChartProps } from 'cdk8s';

/**
 * Props for NixOsVmChart
 *
 * This chart creates a KubeVirt VM with NixOS base image containing pre-configured RustDesk service.
 */
export interface NixOsVmChartProps extends ChartProps {
  /**
   * VM name (used for VM, VMI, DataVolume, and Service names)
   */
  vmName: string;

  /**
   * Kubernetes namespace for VM resources
   * @default "default"
   */
  namespace?: string;

  /**
   * Number of CPU cores allocated to VM
   * @default 2
   */
  cpuCores?: number;

  /**
   * Memory allocated to VM (in Gi)
   * @default "4Gi"
   */
  memory?: string;

  /**
   * Root disk size (must be >= base image size)
   * @default "50Gi"
   */
  storageSize?: string;

  /**
   * Storage class for PVC
   * @default "standard"
   */
  storageClass?: string;

  /**
   * Base image URL (qcow2 format)
   * Must reference a NixOS image with RustDesk pre-configured
   *
   * @example "http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2"
   */
  baseImageUrl: string;

  /**
   * Enable RustDesk remote desktop access
   * When true, exposes RustDesk port 21116 via Service
   *
   * NOTE: RustDesk service is pre-configured in base image, not via cloud-init
   *
   * @default true
   */
  enableRustDesk?: boolean;

  /**
   * RustDesk connection port (for NodePort/ClusterIP service)
   * @default 21116
   */
  rustdeskPort?: number;

  /**
   * Enable Tailscale VPN for VM
   * Requires tailscale-authkey secret in namespace
   *
   * @default false
   */
  enableTailscale?: boolean;

  /**
   * VM running state
   * @default true
   */
  running?: boolean;

  /**
   * ArgoCD sync wave for DataVolume
   * @default -100
   */
  dataVolumeSyncWave?: number;

  /**
   * ArgoCD sync wave for VM resource
   * @default 0
   */
  vmSyncWave?: number;

  /**
   * Additional cloud-init userdata (YAML)
   * Used for SSH keys, users, passwords, Tailscale setup
   *
   * NOTE: Do NOT use for RustDesk configuration (handled by base image)
   *
   * @example
   * ```yaml
   * users:
   *   - name: nixos
   *     ssh_authorized_keys:
   *       - ssh-rsa AAAA...
   * chpasswd:
   *   list: |
   *     nixos:nixos123
   * ```
   */
  cloudInitUserData?: string;

  /**
   * Kubernetes Secret name containing RustDesk password
   * Must be synced via External Secrets Operator before VM starts
   *
   * Secret format:
   * - key: "password"
   * - value: permanent password for RustDesk connections
   *
   * @default "rustdesk-password"
   */
  rustdeskPasswordSecret?: string;

  /**
   * Environment variable name for RustDesk password
   * Cloud-init can reference this via $RUSTDESK_PASSWORD
   *
   * @default "RUSTDESK_PASSWORD"
   */
  rustdeskPasswordEnvVar?: string;
}

/**
 * Example usage in config/applications.ts:
 *
 * ```typescript
 * {
 *   name: 'nixos-dev-vm',
 *   namespace: 'default',
 *   chart: {
 *     type: 'NixOsVmChart',
 *     props: {
 *       vmName: 'nixos-dev-vm',
 *       baseImageUrl: 'http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2',
 *       cpuCores: 2,
 *       memory: '4Gi',
 *       storageSize: '50Gi',
 *       enableRustDesk: true,
 *       enableTailscale: true,
 *       rustdeskPasswordSecret: 'rustdesk-password',
 *       cloudInitUserData: `
 *         users:
 *           - name: nixos
 *             ssh_authorized_keys:
 *               - ssh-rsa AAAA...
 *         chpasswd:
 *           list: |
 *             nixos:$RUSTDESK_PASSWORD
 *       `
 *     }
 *   }
 * }
 * ```
 *
 * Generated Resources:
 *
 * 1. DataVolume (<vmName>-rootdisk):
 *    - Imports base image from baseImageUrl
 *    - Creates PVC of size storageSize
 *    - Sync wave: dataVolumeSyncWave (-100)
 *
 * 2. VirtualMachine (<vmName>):
 *    - Uses DataVolume as root disk
 *    - CPU/Memory from props
 *    - Cloud-init userdata with SSH, users, Tailscale
 *    - Sync wave: vmSyncWave (0)
 *
 * 3. Service (<vmName>-rdp) [if enableRustDesk=true]:
 *    - ClusterIP service exposing port 21116
 *    - Accessible via Tailscale subnet routing
 *    - Optional: NodePort for local testing
 *
 * Validation Rules:
 *
 * - baseImageUrl must be accessible from cluster network
 * - storageSize must be >= base image size (typically >=20Gi)
 * - If enableRustDesk=true, rustdeskPasswordSecret must exist (sync wave -70)
 * - If enableTailscale=true, tailscale-authkey secret must exist
 * - DataVolume must succeed before VM starts (sync wave ordering)
 *
 * Security:
 *
 * - RustDesk password MUST come from Secret (ESO-synced from Azure Key Vault)
 * - Never hardcode passwords in cloudInitUserData
 * - Use environment variable substitution in cloud-init
 * - Secrets must be created before VM (sync wave -70 < 0)
 */

/**
 * Chart implementation checklist:
 *
 * Phase 1: Update base image reference
 * - [ ] Remove cloud-init RustDesk setup from kubevirt-helpers.ts
 * - [ ] Update default baseImageUrl to new image with RustDesk pre-configured
 * - [ ] Ensure DataVolume references updated image
 *
 * Phase 2: Add ESO integration for password
 * - [ ] Create ExternalSecret resource in chart
 * - [ ] Reference Secret in VM environment variables
 * - [ ] Update cloud-init to use $RUSTDESK_PASSWORD env var
 * - [ ] Verify Secret exists before VM starts (sync wave validation)
 *
 * Phase 3: Testing
 * - [ ] Verify DataVolume imports new image successfully
 * - [ ] Verify VM boots with RustDesk service running
 * - [ ] Verify RustDesk service status via SSH
 * - [ ] Test RustDesk connection from client
 * - [ ] Verify password from Secret works for authentication
 */
