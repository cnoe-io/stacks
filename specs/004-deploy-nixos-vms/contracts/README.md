# API Contracts: Deploy NixOS VMs using KubeVirt

**Feature**: 004-deploy-nixos-vms
**Purpose**: Define interface contracts for CDK8s charts, build scripts, and Kubernetes resources

## Overview

This directory contains the "API contracts" for the NixOS VM deployment feature. Since this is an infrastructure-as-code feature rather than a traditional REST API, the contracts define:

1. **CDK8s Chart Interfaces** (`cdk8s-chart-interfaces.ts`): TypeScript interfaces for chart constructor props
2. **Build Script Contracts** (`build-scripts.sh`): Shell script interfaces with input/output specifications
3. **Kubernetes Resource Schemas** (implicitly defined via cdk8s imports)

## Contract Types

### 1. CDK8s Chart Interfaces

Defined in: `cdk8s-chart-interfaces.ts`

**Purpose**: Type-safe infrastructure as code interfaces (Principle I compliance)

**Contracts**:
- `NixOsImageServerChartProps`: Image server deployment configuration
- `NixOsDataVolumeChartProps`: DataVolume import configuration
- `NixOsVmChartProps`: VirtualMachine resource configuration
- `BuildVirtualMachineOptions`: Helper function options
- `buildCloudInitUserData()`: Cloud-init generation function

**Usage**:
```typescript
import { NixOsVmChart } from './charts/apps/nixos-vm-chart';

new NixOsVmChart(app, 'nixos-dev-vm', {
  vmName: 'nixos-dev-vm',
  cpuCores: 2,
  memory: '4Gi',
  enableTailscale: false
});
```

**Guarantees**:
- TypeScript compiler enforces type safety
- IDE provides autocomplete and validation
- Props have sensible defaults (no required parameters except via ChartProps)
- Performance characteristics documented in JSDoc

### 2. Build Script Contracts

Defined in: `build-scripts.sh`

**Purpose**: Reproducible image building and packaging workflows

**Scripts**:
1. **build-kubevirt-image.sh**: Build minimal NixOS qcow2 image
   - Input: NixOS configuration file path
   - Output: Bootable qcow2 image (~1.7GB)
   - Performance: <5 minutes build time

2. **package-image-docker.sh**: Package qcow2 into Docker image
   - Input: qcow2 file path
   - Output: Docker image with nginx + qcow2
   - Performance: <1 minute build, <2 minutes push

3. **deploy-vm-image.sh**: End-to-end workflow
   - Orchestrates: build → package → push → deploy
   - Performance: <10 minutes total

**Exit Codes**:
- `0`: Success
- `1`: Input validation failure
- `2`: Build/execution failure
- `3`: Output validation failure
- `4`: Environment error (missing dependency, insufficient resources)

**Usage**:
```bash
# Build qcow2 image
./scripts/build-kubevirt-image.sh \
  --config /etc/nixos/configurations/kubevirt-minimal.nix \
  --output /tmp/kubevirt-base-image

# Package into Docker
./scripts/package-image-docker.sh \
  --input /tmp/kubevirt-base-image/nixos.qcow2 \
  --tag vpittamp23/nixos-kubevirt-minimal:latest \
  --push

# Or run full workflow
./scripts/deploy-vm-image.sh --push --deploy
```

### 3. Kubernetes Resource Schemas

**Source**: cdk8s imports from KubeVirt/CDI CRDs

**Resources**:
- `VirtualMachine` (kubevirt.io/v1)
- `VirtualMachineInstance` (kubevirt.io/v1)
- `DataVolume` (cdi.kubevirt.io/v1beta1)
- `PersistentVolumeClaim` (v1)
- `Secret` (v1, for cloud-init)
- `Service` (v1, for SSH/RDP access)
- `Deployment` (apps/v1, for image server)

**Import Method**:
```typescript
import * as k8s from './imports/k8s';
import * as kubevirt from './imports/kubevirt.io';  // If using CRD imports
```

**Note**: KubeVirt resources are currently generated using low-level `k8s.ApiObject` with `apiVersion` and `spec` properties. Future improvement: Import KubeVirt CRDs for type-safe resource definitions.

## Contract Validation

### Type Safety (TypeScript)

```bash
cd cdk8s
npm run compile  # Validates all TypeScript interfaces
```

Expected output: No compilation errors

### Build Script Validation

```bash
# Test build-kubevirt-image.sh
./scripts/build-kubevirt-image.sh --help  # Should show usage
./scripts/build-kubevirt-image.sh --config /etc/nixos/configurations/kubevirt-minimal.nix

# Test package-image-docker.sh
./scripts/package-image-docker.sh --help  # Should show usage
./scripts/package-image-docker.sh --input /tmp/kubevirt-base-image/nixos.qcow2
```

Expected exit code: `0` (success)

### Kubernetes Resource Validation

```bash
# Synthesize manifests
cd cdk8s
npx ts-node main-v2.ts

# Dry-run validation
kubectl apply --dry-run=client -f dist/nixos-image-server/manifests/
kubectl apply --dry-run=client -f dist/nixos-dev-vm/manifests/
```

Expected output: No validation errors

## Performance Contracts

All performance guarantees are documented in contracts and validated through success criteria:

| Contract | Performance Guarantee | Success Criterion |
|----------|----------------------|-------------------|
| build-kubevirt-image.sh | <5 min build time | SC-001 |
| package-image-docker.sh | <2 min push time | SC-002 |
| DataVolume import | <3 min for 1.7GB | SC-003 |
| VM boot time | <2 min to SSH | SC-004 |
| Desktop rebuild | <3 min with Attic | SC-007 |
| End-to-end automation | <10 min total | SC-013 |

## Versioning Strategy

Contracts follow semantic versioning principles:

**MAJOR version** (breaking changes):
- Remove chart prop
- Change chart prop type (string → number)
- Change script exit code meanings
- Remove script option

**MINOR version** (backward-compatible additions):
- Add optional chart prop (with default)
- Add script option (with default)
- Add new script

**PATCH version** (non-breaking fixes):
- Fix bug in existing contract
- Clarify documentation
- Add JSDoc comments

Current version: **1.0.0** (initial implementation)

## Future Enhancements

### Potential Contract Additions (P4+)

1. **VM Lifecycle API**: Helper functions for VM operations
   ```typescript
   interface VmLifecycleHelper {
     start(vmName: string, namespace: string): Promise<void>;
     stop(vmName: string, namespace: string): Promise<void>;
     snapshot(vmName: string, snapshotName: string): Promise<void>;
     restore(vmName: string, snapshotName: string): Promise<void>;
   }
   ```

2. **Multi-VM Orchestration**: Chart for VM clusters
   ```typescript
   interface VmClusterChartProps {
     clusterName: string;
     vmCount: number;
     vmTemplate: NixOsVmChartProps;
     loadBalancer?: boolean;
   }
   ```

3. **Desktop Variants**: Support multiple desktop environments
   ```typescript
   type DesktopEnvironment = 'kde' | 'gnome' | 'xfce' | 'i3' | 'none';
   interface NixOsVmChartProps {
     desktopEnvironment?: DesktopEnvironment;
   }
   ```

4. **Production Security Contracts**: ESO integration
   ```typescript
   interface SecureVmChartProps extends NixOsVmChartProps {
     passwordSecretRef: string;  // ExternalSecret name
     sshKeySecretRef: string;    // ExternalSecret name
     networkPolicies: boolean;   // Enable NetworkPolicies
   }
   ```

## References

- [cdk8s TypeScript Guide](https://cdk8s.io/docs/latest/typescript/)
- [KubeVirt API Reference](https://kubevirt.io/api-reference/)
- [CDI API Reference](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)
- [Cloud-init Schema](https://cloudinit.readthedocs.io/en/latest/reference/modules.html)
- Spec: [../spec.md](../spec.md)
- Data Model: [../data-model.md](../data-model.md)
