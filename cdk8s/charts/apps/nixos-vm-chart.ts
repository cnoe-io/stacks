/**
 * NixOS VirtualMachine Chart
 *
 * Creates a VirtualMachine resource using NixOS disk image from DataVolume.
 * Includes cloud-init configuration for dynamic hostname and user setup.
 *
 * User Story: US3 - Launch NixOS Virtual Machine
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { buildVirtualMachine, buildCloudInitUserData } from '../../lib/kubevirt-helpers';
import * as k8s from '../../imports/k8s';

export interface NixOsVmChartProps extends ChartProps {
  /**
   * VM name
   * @default "nixos-dev-vm"
   */
  vmName?: string;

  /**
   * DataVolume name (must exist or be created separately)
   * @default "nixos-dev-datavolume"
   */
  dataVolumeName?: string;

  /**
   * CPU cores
   * @default 2
   */
  cpuCores?: number;

  /**
   * Memory allocation
   * @default "4Gi"
   */
  memory?: string;

  /**
   * Cloud-init user data (YAML string)
   * If not provided, generates default with vpittamp user
   */
  cloudInitUserData?: string;

  /**
   * Target namespace
   * @default "default"
   */
  targetNamespace?: string;

  /**
   * Enable Tailscale exposure for RDP service
   * @default true
   */
  enableTailscale?: boolean;

  /**
   * Tailscale hostname for the RDP service
   * @default "{vmName}-rdp"
   */
  tailscaleHostname?: string;
}

export class NixOsVmChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsVmChartProps = {}) {
    super(scope, id, props);

    const {
      vmName = 'nixos-dev-vm',
      dataVolumeName = 'nixos-dev-datavolume',
      cpuCores = 2,
      memory = '4Gi',
      cloudInitUserData,
      targetNamespace = 'default',
      enableTailscale = true,
      tailscaleHostname,
    } = props;

    // Generate default cloud-init if not provided
    const userData = cloudInitUserData || buildCloudInitUserData(
      vmName,
      'vpittamp',
      [
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer'
      ],
      'nixos123'  // Default password for console access
    );

    // Build VirtualMachine with root disk and cloud-init disk
    const vm = buildVirtualMachine(this, 'vm', {
      name: vmName,
      namespace: targetNamespace,
      runStrategy: 'Manual', // Explicit start/stop control
      cpuCores,
      memory,
      volumes: [
        {
          name: 'rootdisk',
          type: 'dataVolume',
          source: dataVolumeName,
          bus: 'virtio',
        },
        {
          name: 'cloudinitdisk',
          type: 'cloudInit',
          cloudInitData: userData,
          bus: 'virtio',
        },
      ],
      networks: [
        {
          name: 'default',
          type: 'pod',
          interfaceType: 'masquerade',
          ports: [
            {
              name: 'rdp',
              protocol: 'TCP',
              port: 3389,  // RDP port
            },
          ],
        },
      ],
      labels: {
        'app.kubernetes.io/name': vmName,
        'app.kubernetes.io/component': 'virtual-machine',
        'kubevirt.io/vm': vmName,
      },
    });

    // Add sync wave annotation
    vm.metadata.addAnnotation('argocd.argoproj.io/sync-wave', '10');

    // Determine service type and annotations based on Tailscale configuration
    const serviceType = enableTailscale ? 'LoadBalancer' : 'NodePort';
    const hostname = tailscaleHostname || `${vmName}-rdp`;

    const serviceAnnotations: Record<string, string> = {
      'argocd.argoproj.io/sync-wave': '15',  // After VM creation
    };

    // Add Tailscale annotations if enabled
    if (enableTailscale) {
      serviceAnnotations['tailscale.com/expose'] = 'true';
      serviceAnnotations['tailscale.com/hostname'] = hostname;
      // Optional: Add tags for ACL management
      serviceAnnotations['tailscale.com/tags'] = 'tag:k8s-vm,tag:rdp-server';
    }

    // Create Service to expose RDP port
    const rdpService = new k8s.KubeService(this, 'rdp-service', {
      metadata: {
        name: `${vmName}-rdp`,
        namespace: targetNamespace,
        labels: {
          'app.kubernetes.io/name': vmName,
          'app.kubernetes.io/component': 'virtual-machine-service',
        },
        annotations: serviceAnnotations,
      },
      spec: {
        type: serviceType,  // LoadBalancer if Tailscale enabled, NodePort otherwise
        selector: {
          'kubevirt.io/vm': vmName,
        },
        ports: [
          {
            name: 'rdp',
            protocol: 'TCP',
            port: 3389,
            targetPort: k8s.IntOrString.fromNumber(3389),
          },
        ],
      },
    });
  }
}
