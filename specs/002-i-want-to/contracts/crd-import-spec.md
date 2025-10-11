# CRD Import Specification

**Feature**: KubeVirt Installation with NixOS VM Images
**Date**: 2025-10-10

## Overview

This document specifies the Custom Resource Definitions (CRDs) that must be imported into CDK8s for type-safe Kubernetes manifest generation.

## CRD Import Sources

### 1. KubeVirt CRDs

**Source**: `https://github.com/kubevirt/kubevirt/releases/download/v1.3.1/kubevirt-operator.yaml`

**Import Command**:
```bash
cd cdk8s
npx cdk8s import https://github.com/kubevirt/kubevirt/releases/download/v1.3.1/kubevirt-operator.yaml
```

**Generated TypeScript Module**: `cdk8s/imports/kubevirt.io.ts`

**CRDs to Import**:

1. **KubeVirt** (`kubevirt.io/v1`)
   - Cluster-wide configuration for KubeVirt platform
   - Status: Deployed, Failed
   - Key fields: `spec.configuration.developerConfiguration.useEmulation`

2. **VirtualMachine** (`kubevirt.io/v1`)
   - Declarative VM specification
   - Status: Stopped, Starting, Running, Stopping
   - Key fields: `spec.runStrategy`, `spec.template`, `spec.dataVolumeTemplates`

3. **VirtualMachineInstance** (`kubevirt.io/v1`)
   - Ephemeral running VM instance (managed by VirtualMachine controller)
   - Status: Pending, Scheduling, Scheduled, Running, Succeeded, Failed
   - Key fields: `spec.domain`, `spec.volumes`, `status.interfaces`

4. **VirtualMachineInstanceReplicaSet** (`kubevirt.io/v1`)
   - Manages multiple VMI replicas (not used in initial implementation)

**Usage Example**:
```typescript
import { KubeVirt, VirtualMachine } from './imports/kubevirt.io';

// Create KubeVirt CR with software emulation
new KubeVirt(this, 'kubevirt', {
  metadata: { name: 'kubevirt', namespace: 'kubevirt' },
  spec: {
    configuration: {
      developerConfiguration: {
        useEmulation: true, // Required for Kind cluster
      },
    },
  },
});

// Create VirtualMachine with NixOS image
new VirtualMachine(this, 'nixos-vm', {
  metadata: { name: 'nixos-dev-vm', namespace: 'default' },
  spec: {
    runStrategy: 'Manual',
    template: {
      spec: {
        domain: {
          resources: {
            requests: { memory: '4Gi', cpu: '2' },
          },
          devices: {
            disks: [
              { name: 'rootdisk', disk: { bus: 'virtio' } },
              { name: 'cloudinitdisk', disk: { bus: 'virtio' } },
            ],
          },
        },
        volumes: [
          { name: 'rootdisk', dataVolume: { name: 'nixos-dev-datavolume' } },
          {
            name: 'cloudinitdisk',
            cloudInitNoCloud: {
              userData: '#cloud-config\nhostname: nixos-dev\n...',
            },
          },
        ],
      },
    },
  },
});
```

---

### 2. CDI (Containerized Data Importer) CRDs

**Source**: `https://github.com/kubevirt/containerized-data-importer/releases/download/v1.59.0/cdi-operator.yaml`

**Import Command**:
```bash
cd cdk8s
npx cdk8s import https://github.com/kubevirt/containerized-data-importer/releases/download/v1.59.0/cdi-operator.yaml
```

**Generated TypeScript Module**: `cdk8s/imports/cdi.kubevirt.io.ts`

**CRDs to Import**:

1. **CDI** (`cdi.kubevirt.io/v1beta1`)
   - Cluster-wide CDI configuration
   - Status: Deployed, Error
   - Key fields: `spec.config.uploadProxyURLOverride`

2. **DataVolume** (`cdi.kubevirt.io/v1beta1`)
   - High-level abstraction for VM image import
   - Status: Pending, PVCBound, ImportScheduled, ImportInProgress, Succeeded, Failed
   - Key fields: `spec.source`, `spec.pvc`

3. **DataImportCron** (`cdi.kubevirt.io/v1beta1`)
   - Scheduled data imports (not used in initial implementation)

4. **DataSource** (`cdi.kubevirt.io/v1beta1`)
   - Reusable image sources (for future optimization)

**Usage Example**:
```typescript
import { DataVolume } from './imports/cdi.kubevirt.io';

// Create DataVolume for NixOS image import
new DataVolume(this, 'nixos-datavolume', {
  metadata: { name: 'nixos-dev-datavolume', namespace: 'default' },
  spec: {
    source: {
      http: {
        url: 'http://nixos-image-server.default.svc.cluster.local/kubevirt-vm.qcow2',
      },
    },
    pvc: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '20Gi', // 2x image size for overhead
        },
      },
    },
  },
});
```

---

## CDK8s Import Configuration

**File**: `cdk8s/cdk8s.yaml`

```yaml
language: typescript
app: 'npx ts-node main-v2.ts'
imports:
  # Core Kubernetes resources
  - k8s

  # Argo CD
  - argoproj.io

  # External Secrets
  - external-secrets.io

  # Kargo
  - kargo.akuity.io

  # KubeVirt CRDs (NEW)
  - https://github.com/kubevirt/kubevirt/releases/download/v1.3.1/kubevirt-operator.yaml

  # CDI CRDs (NEW)
  - https://github.com/kubevirt/containerized-data-importer/releases/download/v1.59.0/cdi-operator.yaml
```

**Import Execution**:
```bash
cd cdk8s
npm run import  # Runs: cdk8s import
```

---

## Type Validation Requirements

### VirtualMachine Schema Validation

**Required Fields**:
- `metadata.name`: String (DNS-1123 subdomain)
- `spec.template.spec.domain.resources.requests`: Object with `memory` and `cpu`
- `spec.template.spec.volumes`: Array (at least one volume)
- `spec.template.spec.domain.devices.disks`: Array (matching volume names)

**Optional Fields**:
- `spec.runStrategy`: Enum (`Always`, `Manual`, `Halted`, `RerunOnFailure`)
- `spec.dataVolumeTemplates`: Array of DataVolume specs
- `spec.template.spec.networks`: Array (defaults to pod network)

**TypeScript Interface** (Generated):
```typescript
export interface VirtualMachineSpec {
  runStrategy?: 'Always' | 'Manual' | 'Halted' | 'RerunOnFailure';
  dataVolumeTemplates?: DataVolumeSpec[];
  template: {
    metadata?: ObjectMeta;
    spec: VirtualMachineInstanceSpec;
  };
}
```

### DataVolume Schema Validation

**Required Fields**:
- `metadata.name`: String (DNS-1123 subdomain)
- `spec.source`: Object with exactly one source type (`http`, `registry`, `pvc`, `blank`)
- `spec.pvc.resources.requests.storage`: String (Kubernetes quantity format)

**Optional Fields**:
- `spec.pvc.accessModes`: Array (defaults to `['ReadWriteOnce']`)
- `spec.pvc.storageClassName`: String (defaults to cluster default)

**TypeScript Interface** (Generated):
```typescript
export interface DataVolumeSpec {
  source?: {
    http?: { url: string; secretRef?: string };
    registry?: { url: string; secretRef?: string };
    pvc?: { namespace?: string; name: string };
    blank?: {};
  };
  pvc: {
    accessModes?: string[];
    resources: {
      requests: {
        storage: string;
      };
    };
    storageClassName?: string;
  };
}
```

---

## Versioning Strategy

**KubeVirt**: Pin to v1.3.1 initially, test updates in dev cluster before production
**CDI**: Pin to v1.59.0 initially, update with KubeVirt compatibility matrix

**Update Process**:
1. Check KubeVirt/CDI compatibility matrix
2. Update import URLs in `cdk8s.yaml`
3. Run `npm run import` to regenerate TypeScript bindings
4. Fix TypeScript compilation errors (breaking API changes)
5. Test in local Kind cluster
6. Update version in documentation

---

## Import Validation Checklist

- [ ] KubeVirt CRDs imported to `cdk8s/imports/kubevirt.io.ts`
- [ ] CDI CRDs imported to `cdk8s/imports/cdi.kubevirt.io.ts`
- [ ] TypeScript compilation passes (`npm run compile`)
- [ ] Generated types include all required fields
- [ ] VirtualMachine, VirtualMachineInstance, DataVolume types available
- [ ] KubeVirt, CDI cluster-level CRs types available
- [ ] No conflicts with existing imports (k8s, argoproj, external-secrets, kargo)

---

## References

- [KubeVirt CRDs Documentation](https://kubevirt.io/api-reference/)
- [CDI CRDs Documentation](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)
- [CDK8s Import Guide](https://cdk8s.io/docs/latest/cli/import/)
- [KubeVirt API Reference (v1)](https://kubevirt.io/api-reference/v1/)
- [CDI API Reference (v1beta1)](https://pkg.go.dev/kubevirt.io/containerized-data-importer-api/pkg/apis/core/v1beta1)
