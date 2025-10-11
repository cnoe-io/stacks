/**
 * KubeVirt Helper Library
 *
 * Provides reusable builder functions for VirtualMachine resources
 * to simplify VM creation with common patterns (cloud-init, resources, volumes)
 */

import { ApiObject } from 'cdk8s';

export interface VirtualMachineBuilderProps {
  name: string;
  namespace: string;

  // Run strategy (lifecycle management)
  runStrategy?: 'Always' | 'Manual' | 'Halted' | 'RerunOnFailure';

  // Resource allocation
  cpuCores?: number;
  memory?: string; // e.g., "4Gi"

  // Volume configuration
  volumes?: VolumeConfig[];

  // Network configuration
  networks?: NetworkConfig[];

  // Cloud-init configuration
  cloudInit?: CloudInitConfig;

  // Graphics configuration (enables VNC)
  enableGraphics?: boolean;

  // Additional labels and annotations
  labels?: { [key: string]: string };
  annotations?: { [key: string]: string };

  // Termination grace period (seconds)
  terminationGracePeriodSeconds?: number;
}

export interface VolumeConfig {
  name: string;
  type: 'dataVolume' | 'persistentVolumeClaim' | 'cloudInit';

  // For dataVolume or PVC volumes
  source?: string; // DataVolume or PVC name

  // For cloudInit volumes
  cloudInitData?: string;

  // Disk bus type (virtio, sata, scsi)
  bus?: string;
}

export interface NetworkConfig {
  name: string;
  type: 'pod' | 'multus';
  interfaceType?: 'masquerade' | 'bridge';
  // TCP/UDP ports to expose via masquerade (requires masquerade interface type)
  ports?: PortConfig[];
}

export interface PortConfig {
  name?: string;
  protocol?: 'TCP' | 'UDP';
  port: number;  // Port number in the guest VM
}

export interface CloudInitConfig {
  userData?: string; // Cloud-init user data (YAML string)
  secretName?: string; // Secret reference for cloud-init data
}

/**
 * Build a VirtualMachine resource with common configuration patterns
 *
 * @example
 * ```typescript
 * const vm = buildVirtualMachine(this, 'my-vm', {
 *   name: 'nixos-dev-vm',
 *   namespace: 'default',
 *   runStrategy: 'Manual',
 *   cpuCores: 2,
 *   memory: '4Gi',
 *   volumes: [{
 *     name: 'rootdisk',
 *     type: 'dataVolume',
 *     source: 'nixos-dev-datavolume',
 *     bus: 'virtio'
 *   }],
 *   cloudInit: {
 *     userData: `#cloud-config
 * hostname: nixos-dev
 * users:
 *   - name: vpittamp
 *     sudo: ALL=(ALL) NOPASSWD:ALL
 * `
 *   }
 * });
 * ```
 */
export function buildVirtualMachine(
  scope: any,
  id: string,
  props: VirtualMachineBuilderProps
): ApiObject {
  const {
    name,
    namespace,
    runStrategy = 'Manual',
    cpuCores = 2,
    memory = '4Gi',
    volumes = [],
    networks = [{ name: 'default', type: 'pod' }],
    cloudInit,
    enableGraphics = false,
    labels = {},
    annotations = {},
    terminationGracePeriodSeconds = 30,
  } = props;

  // Build disks array from volumes
  const disks = volumes.map((vol, index) => ({
    name: vol.name,
    disk: {
      bus: vol.bus || 'virtio',
    },
    // Set boot order for the first non-cloudInit volume
    ...(vol.type !== 'cloudInit' && index === 0 ? { bootOrder: 1 } : {}),
  }));

  // Build volumes array
  const volumeSpecs = volumes.map(vol => {
    if (vol.type === 'dataVolume' && vol.source) {
      return {
        name: vol.name,
        dataVolume: { name: vol.source },
      };
    } else if (vol.type === 'persistentVolumeClaim' && vol.source) {
      return {
        name: vol.name,
        persistentVolumeClaim: { claimName: vol.source },
      };
    } else if (vol.type === 'cloudInit') {
      return {
        name: vol.name,
        cloudInitNoCloud: vol.cloudInitData
          ? { userData: vol.cloudInitData }
          : cloudInit?.secretName
          ? { secretRef: { name: cloudInit.secretName } }
          : { userData: '' },
      };
    }
    throw new Error(`Invalid volume configuration: ${JSON.stringify(vol)}`);
  });

  // Build networks array
  const networkSpecs = networks.map(net => ({
    name: net.name,
    ...(net.type === 'pod' ? { pod: {} } : {}),
  }));

  // Build interfaces array with port configuration
  const interfaces = networks.map(net => {
    const baseInterface: any = { name: net.name };

    if (net.interfaceType === 'masquerade' || !net.interfaceType) {
      // Masquerade interface with optional port forwarding
      if (net.ports && net.ports.length > 0) {
        baseInterface.masquerade = {};
        baseInterface.ports = net.ports.map(p => ({
          ...(p.name ? { name: p.name } : {}),
          protocol: p.protocol || 'TCP',
          port: p.port,
        }));
      } else {
        baseInterface.masquerade = {};
      }
    } else if (net.interfaceType === 'bridge') {
      baseInterface.bridge = {};
    }

    return baseInterface;
  });

  const spec: any = {
    runStrategy,
    template: {
      metadata: {
        labels: {
          'kubevirt.io/domain': name,
          ...labels,
        },
        annotations,
      },
      spec: {
        domain: {
          resources: {
            requests: {
              memory,
              cpu: `${cpuCores}`,
            },
          },
          devices: {
            disks,
            interfaces: interfaces.length > 0 ? interfaces : undefined,
            ...(enableGraphics ? {
              autoattachGraphicsDevice: true,
              inputs: [{
                type: 'tablet',
                bus: 'usb',
                name: 'tablet'
              }]
            } : {}),
          },
        },
        networks: networkSpecs.length > 0 ? networkSpecs : undefined,
        volumes: volumeSpecs,
        terminationGracePeriodSeconds,
      },
    },
  };

  return new ApiObject(scope, id, {
    apiVersion: 'kubevirt.io/v1',
    kind: 'VirtualMachine',
    metadata: {
      name,
      namespace,
      labels: {
        'app.kubernetes.io/name': name,
        ...labels,
      },
      annotations,
    },
    spec,
  });
}

/**
 * Build cloud-init user data for NixOS VMs
 *
 * @param hostname - VM hostname
 * @param username - Primary user name
 * @param sshKeys - SSH authorized keys (optional)
 */
export function buildCloudInitUserData(
  hostname: string,
  username: string,
  sshKeys?: string[],
  password?: string
): string {
  // Generate proper YAML format, not JSON
  let userData = `#cloud-config
hostname: ${hostname}
users:
  - name: ${username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash`;

  if (sshKeys && sshKeys.length > 0) {
    userData += '\n    ssh_authorized_keys:';
    sshKeys.forEach(key => {
      userData += `\n      - ${key}`;
    });
  }

  if (password) {
    userData += `\n    passwd: ${password}`;
    userData += '\n    lock_passwd: false';
  }

  // Also set root password if provided
  if (password) {
    userData += `\n  - name: root
    passwd: ${password}
    lock_passwd: false`;
  }

  return userData;
}

/**
 * Build dataVolumeTemplates for ephemeral VM disks
 * (PVCs owned by VM, deleted when VM deleted)
 *
 * @example
 * ```typescript
 * const vm = new VirtualMachine(this, 'vm', {
 *   spec: {
 *     dataVolumeTemplates: buildDataVolumeTemplates({
 *       name: 'my-vm-disk',
 *       imageUrl: 'http://image-server/nixos.qcow2',
 *       storageSize: '20Gi'
 *     }),
 *     // ... rest of VM spec
 *   }
 * });
 * ```
 */
export function buildDataVolumeTemplates(props: {
  name: string;
  imageUrl: string;
  storageSize?: string;
  storageClassName?: string;
}): any[] {
  return [
    {
      metadata: { name: props.name },
      spec: {
        source: {
          http: { url: props.imageUrl },
        },
        pvc: {
          accessModes: ['ReadWriteOnce'],
          resources: {
            requests: {
              storage: props.storageSize || '20Gi',
            },
          },
          ...(props.storageClassName ? { storageClassName: props.storageClassName } : {}),
        },
      },
    },
  ];
}
