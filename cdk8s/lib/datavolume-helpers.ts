/**
 * DataVolume Helper Library
 *
 * Provides reusable builder functions for DataVolume resources
 * to simplify VM disk image imports from HTTP, OCI registry, or PVC sources
 */

import { DataVolume } from '../imports/cdi.kubevirt.io';

export interface DataVolumeBuilderProps {
  name: string;
  namespace: string;

  // Source configuration (one required)
  source: DataVolumeSource;

  // Storage configuration
  storageSize?: string; // e.g., "20Gi"
  storageClassName?: string;
  accessModes?: ('ReadWriteOnce' | 'ReadOnlyMany' | 'ReadWriteMany')[];

  // Additional metadata
  labels?: { [key: string]: string };
  annotations?: { [key: string]: string };

  // Content type (kubevirt auto-detects qcow2, raw, vmdk)
  contentType?: 'kubevirt' | 'archive';
}

export type DataVolumeSource =
  | { type: 'http'; url: string; secretRef?: string }
  | { type: 'registry'; url: string; secretRef?: string; certConfigMap?: string }
  | { type: 'pvc'; namespace?: string; name: string }
  | { type: 'blank' };

/**
 * Build a DataVolume resource for importing VM disk images
 *
 * @example
 * ```typescript
 * // HTTP source
 * const dv = buildDataVolume(this, 'nixos-dv', {
 *   name: 'nixos-dev-datavolume',
 *   namespace: 'default',
 *   source: {
 *     type: 'http',
 *     url: 'http://image-server.default.svc.cluster.local/nixos.qcow2'
 *   },
 *   storageSize: '20Gi'
 * });
 *
 * // Registry source
 * const dv = buildDataVolume(this, 'nixos-dv', {
 *   name: 'nixos-dev-datavolume',
 *   namespace: 'default',
 *   source: {
 *     type: 'registry',
 *     url: 'docker://gitea.cnoe.localtest.me:8443/giteaadmin/nixos:latest',
 *     secretRef: 'docker-config'
 *   },
 *   storageSize: '20Gi'
 * });
 * ```
 */
export function buildDataVolume(
  scope: any,
  id: string,
  props: DataVolumeBuilderProps
): DataVolume {
  const {
    name,
    namespace,
    source,
    storageSize = '20Gi',
    storageClassName,
    accessModes = ['ReadWriteOnce'],
    labels = {},
    annotations = {},
    contentType = 'kubevirt',
  } = props;

  // Build source specification
  let sourceSpec: any = {};
  switch (source.type) {
    case 'http':
      sourceSpec = {
        http: {
          url: source.url,
          ...(source.secretRef ? { secretRef: source.secretRef } : {}),
        },
      };
      break;
    case 'registry':
      sourceSpec = {
        registry: {
          url: source.url,
          ...(source.secretRef ? { secretRef: source.secretRef } : {}),
          ...(source.certConfigMap ? { certConfigMap: source.certConfigMap } : {}),
        },
      };
      break;
    case 'pvc':
      sourceSpec = {
        pvc: {
          name: source.name,
          ...(source.namespace ? { namespace: source.namespace } : {}),
        },
      };
      break;
    case 'blank':
      sourceSpec = { blank: {} };
      break;
    default:
      throw new Error(`Invalid DataVolume source type: ${JSON.stringify(source)}`);
  }

  const spec: any = {
    source: sourceSpec,
    pvc: {
      accessModes,
      resources: {
        requests: {
          storage: storageSize,
        },
      },
      ...(storageClassName ? { storageClassName } : {}),
    },
    contentType,
  };

  return new DataVolume(scope, id, {
    metadata: {
      name,
      namespace,
      labels: {
        'app.kubernetes.io/name': name,
        'app.kubernetes.io/component': 'datavolume',
        ...labels,
      },
      annotations,
    },
    spec,
  });
}

/**
 * Build an HTTP source DataVolume for NixOS qcow2 images
 * Convenience wrapper for HTTP-based image imports
 *
 * @param scope - Construct scope
 * @param id - Construct ID
 * @param name - DataVolume name
 * @param namespace - Namespace
 * @param imageUrl - HTTP URL to qcow2 image
 * @param storageSize - PVC storage size (default: "20Gi")
 */
export function buildHttpDataVolume(
  scope: any,
  id: string,
  name: string,
  namespace: string,
  imageUrl: string,
  storageSize?: string
): DataVolume {
  return buildDataVolume(scope, id, {
    name,
    namespace,
    source: {
      type: 'http',
      url: imageUrl,
    },
    storageSize,
  });
}

/**
 * Build a registry source DataVolume for OCI-stored VM images
 * Convenience wrapper for OCI registry-based image imports
 *
 * @param scope - Construct scope
 * @param id - Construct ID
 * @param name - DataVolume name
 * @param namespace - Namespace
 * @param registryUrl - OCI registry URL (e.g., "docker://registry.example.com/image:tag")
 * @param secretRef - Secret name containing registry credentials
 * @param storageSize - PVC storage size (default: "20Gi")
 */
export function buildRegistryDataVolume(
  scope: any,
  id: string,
  name: string,
  namespace: string,
  registryUrl: string,
  secretRef: string,
  storageSize?: string
): DataVolume {
  return buildDataVolume(scope, id, {
    name,
    namespace,
    source: {
      type: 'registry',
      url: registryUrl,
      secretRef,
    },
    storageSize,
  });
}

/**
 * Build a PVC clone DataVolume (copy existing PVC)
 * Useful for creating VM snapshots or cloning VMs
 *
 * @param scope - Construct scope
 * @param id - Construct ID
 * @param name - DataVolume name
 * @param namespace - Target namespace
 * @param sourcePvcName - Source PVC name
 * @param sourcePvcNamespace - Source PVC namespace (optional, defaults to same namespace)
 * @param storageSize - PVC storage size (default: "20Gi")
 */
export function buildPvcCloneDataVolume(
  scope: any,
  id: string,
  name: string,
  namespace: string,
  sourcePvcName: string,
  sourcePvcNamespace?: string,
  storageSize?: string
): DataVolume {
  return buildDataVolume(scope, id, {
    name,
    namespace,
    source: {
      type: 'pvc',
      name: sourcePvcName,
      namespace: sourcePvcNamespace,
    },
    storageSize,
  });
}

/**
 * Build a blank DataVolume (empty PVC)
 * Useful for creating scratch disks or data volumes for VMs
 *
 * @param scope - Construct scope
 * @param id - Construct ID
 * @param name - DataVolume name
 * @param namespace - Namespace
 * @param storageSize - PVC storage size (default: "10Gi")
 */
export function buildBlankDataVolume(
  scope: any,
  id: string,
  name: string,
  namespace: string,
  storageSize?: string
): DataVolume {
  return buildDataVolume(scope, id, {
    name,
    namespace,
    source: { type: 'blank' },
    storageSize: storageSize || '10Gi',
  });
}
