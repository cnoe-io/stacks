/**
 * CDK8s Chart Interface Contracts
 *
 * Feature: 004-deploy-nixos-vms
 * Purpose: Define TypeScript interfaces for CDK8s charts
 *
 * These interfaces are the "API contracts" for infrastructure as code.
 * They define the input parameters (props) and expected behavior for
 * chart constructors.
 */

import { ChartProps } from 'cdk8s';

/**
 * NixOS Image Server Chart
 *
 * Deploys an nginx HTTP server serving qcow2 images for DataVolume imports.
 *
 * User Story: US2 - Create NixOS-based VM Image
 * Requirements: FR-011 through FR-015 (Image Distribution)
 */
export interface NixOsImageServerChartProps extends ChartProps {
  /**
   * Docker image containing nginx + qcow2 files
   *
   * Image must contain:
   * - nginx web server
   * - qcow2 file at /usr/share/nginx/html/nixos.qcow2
   *
   * @default "vpittamp23/nixos-kubevirt-minimal:latest"
   * @example "vpittamp23/nixos-kubevirt-minimal:v1.0.0"
   */
  image?: string;

  /**
   * Number of replicas for image server deployment
   *
   * Constraints:
   * - Must be >= 1 for availability
   * - Single replica sufficient for development
   *
   * @default 1
   */
  replicas?: number;

  /**
   * Target namespace for deployment
   *
   * @default "default"
   */
  namespace?: string;
}

/**
 * Expected Outputs:
 * - Deployment: nixos-image-server (sync wave: -50)
 * - Service: nixos-image-server (ClusterIP on port 80)
 * - DNS Name: nixos-image-server.default.svc.cluster.local
 *
 * Performance Guarantees:
 * - Pod ready within 30 seconds
 * - HTTP response <100ms for qcow2 HEAD request
 * - Download speed: 100-500 MB/s in-cluster
 *
 * Success Criteria: FR-015, SC-002
 */

/**
 * NixOS DataVolume Chart
 *
 * Creates a CDI DataVolume resource to import qcow2 image from HTTP source
 * into a PersistentVolumeClaim.
 *
 * User Story: US2 - Create NixOS-based VM Image
 * Requirements: FR-016 through FR-020 (DataVolume Import)
 */
export interface NixOsDataVolumeChartProps extends ChartProps {
  /**
   * DataVolume resource name
   *
   * Constraints:
   * - Must be valid Kubernetes resource name
   * - Will be used as PVC name (auto-created by CDI)
   *
   * @default "nixos-dev-datavolume"
   */
  dataVolumeName?: string;

  /**
   * HTTP URL to qcow2 image
   *
   * URL must:
   * - Be reachable from CDI importer pod
   * - Serve valid qcow2 file
   * - Support HTTP HEAD requests (for size check)
   *
   * @default "http://nixos-image-server.default.svc.cluster.local/nixos.qcow2"
   * @example "http://nixos-image-server.default.svc.cluster.local/nixos-custom.qcow2"
   */
  imageServerUrl?: string;

  /**
   * PVC storage size request
   *
   * Constraints:
   * - Must be >= 2x compressed qcow2 size (for expansion + buffer)
   * - Minimum 20Gi for desktop installations
   *
   * @default "20Gi"
   */
  storageSize?: string;

  /**
   * StorageClass name for PVC provisioning
   *
   * If not specified, uses cluster's default StorageClass.
   * StorageClass must support:
   * - ReadWriteOnce access mode
   * - Dynamic provisioning
   *
   * @default undefined (uses cluster default)
   * @example "local-path", "gp3", "standard"
   */
  storageClassName?: string;

  /**
   * Target namespace for DataVolume and PVC
   *
   * @default "default"
   */
  targetNamespace?: string;
}

/**
 * Expected Outputs:
 * - DataVolume: <dataVolumeName> (sync wave: 0)
 * - PVC: <dataVolumeName> (auto-created by CDI)
 *
 * Performance Guarantees:
 * - Import time <3 minutes for 1.7GB qcow2
 * - PVC ready within 5 minutes of DataVolume creation
 *
 * Success Criteria: FR-020, SC-003
 */

/**
 * NixOS VirtualMachine Chart
 *
 * Creates a KubeVirt VirtualMachine resource with cloud-init configuration
 * and Service for SSH/RDP access.
 *
 * User Story: US3 - Launch NixOS Virtual Machine
 * Requirements: FR-021 through FR-059 (VM, cloud-init, Services, GitOps)
 */
export interface NixOsVmChartProps extends ChartProps {
  /**
   * VirtualMachine resource name
   *
   * Used for:
   * - VM resource name
   * - VMI resource name
   * - Service name prefix (<vmName>-rdp)
   * - Default hostname in cloud-init
   *
   * @default "nixos-dev-vm"
   */
  vmName?: string;

  /**
   * DataVolume name for root disk
   *
   * DataVolume must:
   * - Exist or be created in same sync wave cycle
   * - Be in Succeeded state before VM starts
   * - Contain bootable qcow2 with GRUB on /dev/vda
   *
   * @default "nixos-dev-datavolume"
   */
  dataVolumeName?: string;

  /**
   * Number of CPU cores
   *
   * Constraints:
   * - Must be >= 1
   * - Must be within node allocatable CPU
   *
   * @default 2
   */
  cpuCores?: number;

  /**
   * Memory allocation
   *
   * Format: Kubernetes Quantity string (e.g., "4Gi", "8192Mi")
   *
   * Constraints:
   * - Must be >= 2Gi for NixOS + desktop
   * - Must be within node allocatable memory
   *
   * @default "4Gi"
   */
  memory?: string;

  /**
   * Cloud-init user data (YAML string)
   *
   * If not provided, generates default cloud-config with:
   * - hostname: <vmName>
   * - user: vpittamp (sudo, SSH key from 1Password k8s_ed_test)
   * - password: nixos123 (for console access)
   *
   * Format: cloud-config YAML (must start with "#cloud-config")
   *
   * @default undefined (generates default)
   * @example
   * ```yaml
   * #cloud-config
   * hostname: my-vm
   * users:
   *   - name: myuser
   *     sudo: ALL=(ALL) NOPASSWD:ALL
   *     ssh_authorized_keys:
   *       - ssh-ed25519 AAAA...
   * ```
   */
  cloudInitUserData?: string;

  /**
   * Target namespace for VM resources
   *
   * @default "default"
   */
  targetNamespace?: string;

  /**
   * Enable Tailscale exposure for RDP service
   *
   * When enabled:
   * - Service type: LoadBalancer (with loadBalancerClass: tailscale)
   * - Annotations: tailscale.com/expose, tailscale.com/hostname, tailscale.com/tags
   *
   * When disabled:
   * - Service type: NodePort
   *
   * @default false
   */
  enableTailscale?: boolean;

  /**
   * Tailscale hostname for RDP service
   *
   * Only used if enableTailscale is true.
   *
   * @default "{vmName}-rdp"
   */
  tailscaleHostname?: string;

  /**
   * VM run strategy
   *
   * - Always: VM starts automatically and restarts on failure
   * - Manual: Explicit start/stop control via virtctl
   * - RerunOnFailure: Restart only on failure
   * - Halted: VM remains stopped
   *
   * @default "Always"
   */
  runStrategy?: 'Always' | 'Manual' | 'RerunOnFailure' | 'Halted';

  /**
   * Enable VNC graphics device
   *
   * When enabled:
   * - VNC server available via virtctl vnc
   * - Requires VNC client for access
   *
   * When disabled:
   * - No graphics device (headless)
   * - Serial console only (virtctl console)
   *
   * @default true
   */
  enableGraphics?: boolean;
}

/**
 * Expected Outputs:
 * - Secret: <vmName>-cloudinit (sync wave: 5)
 * - VirtualMachine: <vmName> (sync wave: 10)
 * - Service: <vmName>-rdp (sync wave: 15)
 * - VirtualMachineInstance: <vmName> (auto-created by KubeVirt)
 *
 * Performance Guarantees:
 * - VM boot time <2 minutes from DataVolume ready
 * - SSH accessible within 30 seconds of VMI Running
 * - Service ready within 30 seconds of VMI Running
 *
 * Success Criteria: FR-029, FR-036, FR-041, SC-004, SC-006
 */

/**
 * Helper Function Contracts
 *
 * These functions are used internally by charts but define important contracts.
 */

/**
 * Build VirtualMachine resource with KubeVirt CRDs
 *
 * Location: cdk8s/lib/kubevirt-helpers.ts
 *
 * @param scope - CDK8s construct scope
 * @param id - Resource identifier
 * @param options - VM configuration options
 * @returns KubeVirtualMachine resource
 *
 * Requirements: FR-021 through FR-029
 */
export interface BuildVirtualMachineOptions {
  name: string;
  namespace: string;
  runStrategy: 'Always' | 'Manual' | 'RerunOnFailure' | 'Halted';
  cpuCores: number;
  memory: string;
  enableGraphics: boolean;
  volumes: Array<{
    name: string;
    type: 'dataVolume' | 'cloudInit';
    source?: string; // DataVolume name for type=dataVolume
    cloudInitSecretName?: string; // Secret name for type=cloudInit
    bus: 'virtio' | 'scsi' | 'sata';
  }>;
  networks: Array<{
    name: string;
    type: 'pod' | 'bridge' | 'multus';
    interfaceType: 'masquerade' | 'bridge' | 'sriov';
    ports?: Array<{
      name: string;
      protocol: 'TCP' | 'UDP';
      port: number;
    }>;
  }>;
  labels?: Record<string, string>;
}

/**
 * Build cloud-init user data YAML
 *
 * Location: cdk8s/lib/kubevirt-helpers.ts
 *
 * @param hostname - VM hostname
 * @param username - Primary user account name
 * @param sshKeys - Array of SSH public keys
 * @param password - User password (plain text)
 * @param installDesktop - Whether to install desktop environment via cloud-init
 * @returns cloud-config YAML string
 *
 * Requirements: FR-030 through FR-036
 */
export function buildCloudInitUserData(
  hostname: string,
  username: string,
  sshKeys: string[],
  password: string,
  installDesktop: boolean
): string;

/**
 * Output Format:
 * ```yaml
 * #cloud-config
 * hostname: <hostname>
 * users:
 *   - name: <username>
 *     sudo: ALL=(ALL) NOPASSWD:ALL
 *     shell: /bin/bash
 *     ssh_authorized_keys:
 *       - <sshKeys[0]>
 *       - <sshKeys[1]>
 * chpasswd:
 *   list: |
 *     <username>:<password>
 *     root:<password>
 *   expire: false
 * ```
 *
 * Note: installDesktop=false for minimal base image (desktop via nixos-rebuild)
 */
