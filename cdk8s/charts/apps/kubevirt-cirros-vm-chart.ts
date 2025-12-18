/**
 * KubeVirt Cirros VM Chart (Smoke Test)
 *
 * Deploys a tiny containerDisk-based VM to validate that KubeVirt is functional
 * before attempting larger qcow2/DataVolume-based NixOS VMs.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { buildVirtualMachine } from '../../lib/kubevirt-helpers';

export interface KubeVirtCirrosVmChartProps extends ChartProps {
  /**
   * VM name
   * @default "kv-cirros"
   */
  vmName?: string;

  /**
   * Target namespace
   * @default "default"
   */
  namespace?: string;

  /**
   * ContainerDisk image to boot
   * @default "quay.io/kubevirt/cirros-container-disk-demo"
   */
  containerDiskImage?: string;

  /**
   * Run strategy for the VM
   * @default "Always"
   */
  runStrategy?: 'Always' | 'Manual' | 'RerunOnFailure' | 'Halted';
}

export class KubeVirtCirrosVmChart extends Chart {
  constructor(scope: Construct, id: string, props: KubeVirtCirrosVmChartProps = {}) {
    super(scope, id, props);

    const {
      vmName = 'kv-cirros',
      namespace = 'default',
      containerDiskImage = 'quay.io/kubevirt/cirros-container-disk-demo',
      runStrategy = 'Always',
    } = props;

    const vm = buildVirtualMachine(this, 'vm', {
      name: vmName,
      namespace,
      runStrategy,
      cpuCores: 1,
      memory: '256Mi',
      enableGraphics: false,
      volumes: [
        {
          name: 'containerdisk',
          type: 'containerDisk',
          containerDiskImage,
          bus: 'virtio',
        },
      ],
      networks: [
        {
          name: 'default',
          type: 'pod',
          interfaceType: 'masquerade',
        },
      ],
      labels: {
        'app.kubernetes.io/name': vmName,
        'app.kubernetes.io/component': 'kubevirt-smoke-test',
        'kubevirt.io/vm': vmName,
      },
    });

    vm.metadata.addAnnotation('argocd.argoproj.io/sync-wave', '0');
  }
}

