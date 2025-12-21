/**
 * NixOS DataVolume Chart
 *
 * Creates a DataVolume to import NixOS qcow2 image from HTTP server into a PVC.
 * The imported PVC can be used as a root disk for VirtualMachines.
 *
 * User Story: US2 - Create NixOS-based VM Image
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { buildHttpDataVolume } from '../../lib/datavolume-helpers';

export interface NixOsDataVolumeChartProps extends ChartProps {
  /**
   * DataVolume name
   * @default "nixos-dev-datavolume"
   */
  dataVolumeName?: string;

  /**
   * HTTP URL to qcow2 image
   * @default "http://nixos-image-server.default.svc.cluster.local/nixos.qcow2"
   */
  imageUrl?: string;

  /**
   * PVC storage size (should be 2x image size for overhead)
   * @default "50Gi"
   */
  storageSize?: string;

  /**
   * Target namespace
   * @default "default"
   */
  targetNamespace?: string;
}

export class NixOsDataVolumeChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsDataVolumeChartProps = {}) {
    super(scope, id, props);

    const {
      dataVolumeName = 'nixos-dev-datavolume',
      imageUrl = 'http://nixos-image-server.default.svc.cluster.local/nixos.qcow2',
      storageSize = '50Gi',
      targetNamespace = 'default',
    } = props;

    // Create DataVolume for NixOS image import
    const dataVolume = buildHttpDataVolume(
      this,
      'datavolume',
      dataVolumeName,
      targetNamespace,
      imageUrl,
      storageSize,
      {
        'cdi.kubevirt.io/storage.import.requiresScratch': 'false',
      }
    );

    // Add sync wave annotation for ArgoCD ordering
    dataVolume.metadata.addAnnotation('argocd.argoproj.io/sync-wave', '0');
  }
}
