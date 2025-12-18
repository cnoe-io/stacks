/**
 * NixOS Sway VM Chart (nixos-config)
 *
 * Boots a NixOS qcow2 image (imported via CDI DataVolume) as a KubeVirt VM.
 * Designed for images built from github:vpittamp/nixos-config (e.g. hetzner-sway-qcow2).
 *
 * Notes:
 * - Does NOT rely on cloud-init (nixos-config hetzner config has cloud-init disabled)
 * - Exposes SSH + VNC via a NodePort Service for easy access on Kind
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { buildVirtualMachine } from '../../lib/kubevirt-helpers';
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
    } = props;

    const vm = buildVirtualMachine(this, 'vm', {
      name: vmName,
      namespace,
      runStrategy,
      cpuCores,
      memory,
      enableGraphics,
      volumes: [
        {
          name: 'rootdisk',
          type: 'dataVolume',
          source: dataVolumeName,
          bus: 'virtio',
        },
      ],
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

