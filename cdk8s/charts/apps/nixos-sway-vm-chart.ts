/**
 * NixOS Sway VM Chart (nixos-config)
 *
 * Boots a NixOS qcow2 image (imported via CDI DataVolume) as a KubeVirt VM.
 * Designed for images built from github:vpittamp/nixos-config (e.g. kubevirt-minimal).
 *
 * Features:
 * - Cloud-init for auto-configuration (kubevirt-minimal has cloud-init enabled)
 * - Optional Tailscale integration for stable access via svc:nixos-vm
 * - SSH + VNC exposed via NodePort Service
 *
 * Tailscale Integration:
 * - When enableTailscale=true, the VM joins your Tailnet on boot
 * - Access via: tailscale ssh nixos-vm or ssh nixos-vm.<tailnet>.ts.net
 * - Requires TAILSCALE-AUTH-KEY-VM secret in Azure Key Vault
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { buildVirtualMachine, buildCloudInitUserData } from '../../lib/kubevirt-helpers';
import * as k8s from '../../imports/k8s';

export interface NixOsSwayVmChartProps extends ChartProps {
  /**
   * VM name
   * @default "nixos-sway-vm"
   */
  vmName?: string;

  /**
   * DataVolume name that contains the imported qcow2
   * @default "nixos-sway-datavolume"
   */
  dataVolumeName?: string;

  /**
   * Target namespace
   * @default "default"
   */
  namespace?: string;

  /**
   * CPU cores
   * @default 4
   */
  cpuCores?: number;

  /**
   * Memory allocation
   * @default "6Gi"
   */
  memory?: string;

  /**
   * Run strategy for the VM
   * @default "Always"
   */
  runStrategy?: 'Always' | 'Manual' | 'RerunOnFailure' | 'Halted';

  /**
   * Enable graphics device (VNC)
   * @default true
   */
  enableGraphics?: boolean;

  /**
   * Service type to expose SSH/VNC
   * @default "NodePort"
   */
  serviceType?: 'NodePort' | 'ClusterIP';

  /**
   * Enable Tailscale for stable access via Tailnet
   * When enabled, VM joins Tailscale on boot and is accessible via:
   * - tailscale ssh nixos-vm
   * - ssh nixos-vm.<tailnet>.ts.net
   * @default true
   */
  enableTailscale?: boolean;

  /**
   * Tailscale auth key for automatic registration
   * Passed at synthesis time (should come from env var, not hardcoded)
   * If not provided, Tailscale will require manual OAuth authentication
   */
  tailscaleAuthKey?: string;

  /**
   * Tailscale hostname for the VM
   * @default vmName (e.g., "nixos-sway-vm")
   */
  tailscaleHostname?: string;
}

export class NixOsSwayVmChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsSwayVmChartProps = {}) {
    super(scope, id, props);

    const {
      vmName = 'nixos-sway-vm',
      dataVolumeName = 'nixos-sway-datavolume',
      namespace = 'default',
      cpuCores = 4,
      memory = '6Gi',
      runStrategy = 'Always',
      enableGraphics = true,
      serviceType = 'NodePort',
      enableTailscale = true,
      tailscaleAuthKey,
      tailscaleHostname,
    } = props;

    // Build cloud-init user data with Tailscale support
    // The kubevirt-minimal image has cloud-init and Tailscale pre-installed
    const cloudInitUserData = buildCloudInitUserData(
      tailscaleHostname || vmName,  // hostname for the VM
      'vpittamp',                   // username
      [                             // SSH authorized keys
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer',
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com',
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7 1password-git-signing',
      ],
      undefined,                    // password (use SSH keys)
      false,                        // installDesktop (use nixos-rebuild for desktop)
      enableTailscale,              // enableTailscale
      tailscaleAuthKey,             // tailscaleAuthKey (optional)
    );

    // Volumes for the VM
    const volumes = [
      {
        name: 'rootdisk',
        type: 'dataVolume' as const,
        source: dataVolumeName,
        bus: 'virtio',
      },
      // Cloud-init volume with Tailscale configuration
      {
        name: 'cloudinit',
        type: 'cloudInit' as const,
        cloudInitData: cloudInitUserData,
      },
    ];

    const vm = buildVirtualMachine(this, 'vm', {
      name: vmName,
      namespace,
      runStrategy,
      cpuCores,
      memory,
      enableGraphics,
      volumes,
      networks: [
        {
          name: 'default',
          type: 'pod',
          interfaceType: 'masquerade',
          ports: [
            { name: 'ssh', protocol: 'TCP', port: 22 },
            { name: 'vnc', protocol: 'TCP', port: 5900 },
          ],
        },
      ],
      labels: {
        'app.kubernetes.io/name': vmName,
        'app.kubernetes.io/component': 'virtual-machine',
        'kubevirt.io/vm': vmName,
        ...(enableTailscale && { 'tailscale.com/enabled': 'true' }),
      },
    });

    vm.metadata.addAnnotation('argocd.argoproj.io/sync-wave', '10');

    // Expose SSH + VNC on the virt-launcher pod via Service
    new k8s.KubeService(this, 'ssh-vnc-service', {
      metadata: {
        name: `${vmName}-ssh-vnc`,
        namespace,
        labels: {
          'app.kubernetes.io/name': vmName,
          'app.kubernetes.io/component': 'virtual-machine-service',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '15',
        },
      },
      spec: {
        type: serviceType,
        selector: {
          'kubevirt.io/vm': vmName,
        },
        ports: [
          {
            name: 'ssh',
            protocol: 'TCP',
            port: 22,
            targetPort: k8s.IntOrString.fromNumber(22),
          },
          {
            name: 'vnc',
            protocol: 'TCP',
            port: 5900,
            targetPort: k8s.IntOrString.fromNumber(5900),
          },
        ],
      },
    });
  }
}

