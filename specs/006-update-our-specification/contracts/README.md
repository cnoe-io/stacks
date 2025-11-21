# Contracts: RustDesk Base Image Integration

**Feature**: 006-update-our-specification
**Date**: 2025-10-14

## Overview

This directory defines the API contracts for the RustDesk base image integration feature. Contracts specify the interfaces, data formats, and validation rules that implementation must follow.

## Contract Files

### 1. `nixos-rustdesk-module.nix`

**Purpose**: NixOS module API for RustDesk service configuration in base image

**Type**: Nix module options (declarative configuration)

**Key Interfaces**:
- `services.rustdesk.enable`: Master enable switch
- `services.rustdesk.enableSystemService`: Run as system service (headless mode)
- `services.rustdesk.headlessMode`: Enable headless mode (no GUI)
- `services.rustdesk.extraEnvironment`: Environment variables (e.g., LIBGL_ALWAYS_SOFTWARE)

**Validation**:
- If `enableSystemService = true`, then `user` must be "root"
- If `headlessMode = true`, then `allow-linux-headless` option is set automatically
- `firewallPorts` must include 21116 if `enableDirectIpAccess = true`

**Consumer**: NixOS base image flake.nix (Hetzner host)

---

### 2. `cdk8s-nixos-vm-chart.ts`

**Purpose**: TypeScript interface for NixOS VM CDK8s chart props

**Type**: TypeScript interface (compile-time contract)

**Key Interfaces**:
- `NixOsVmChartProps.baseImageUrl`: URL to qcow2 image with RustDesk pre-configured
- `NixOsVmChartProps.enableRustDesk`: Enable RustDesk service port exposure
- `NixOsVmChartProps.rustdeskPasswordSecret`: Kubernetes Secret name for password
- `NixOsVmChartProps.cloudInitUserData`: Cloud-init YAML (excluding RustDesk setup)

**Validation**:
- `baseImageUrl` must be accessible from cluster network
- `storageSize` must be >= base image size
- If `enableRustDesk=true`, `rustdeskPasswordSecret` must exist (sync wave -70)
- `cloudInitUserData` MUST NOT include RustDesk configuration (handled by base image)

**Consumer**: `config/applications.ts` (application configuration)

---

### 3. `external-secret-rustdesk.yaml`

**Purpose**: ESO ExternalSecret manifest for RustDesk password

**Type**: Kubernetes CRD (YAML manifest)

**Key Interfaces**:
- `spec.secretStoreRef`: Reference to Azure Key Vault ClusterSecretStore
- `spec.data[].remoteRef.key`: Azure Key Vault secret name (`RUSTDESK-PASSWORD`)
- `spec.target.name`: Kubernetes Secret name (`rustdesk-password`)

**Validation**:
- ClusterSecretStore `azure-keyvault-store` must exist (wave -90)
- Azure Key Vault secret `RUSTDESK-PASSWORD` must exist
- ExternalSecret must sync successfully (status.conditions[0].status = "True")
- Sync wave -70 ensures Secret exists before VM (wave 0)

**Consumer**: NixOS VM chart (references Secret in environment variables)

---

## Contract Relationships

```
┌──────────────────────────┐
│ nixos-rustdesk-module.nix│
│ (Nix module contract)    │
└────────────┬─────────────┘
             │ used by
             ▼
      ┌──────────────┐
      │ Base Image   │ (qcow2 file in MinIO)
      │ Build        │
      └──────┬───────┘
             │ referenced by
             ▼
┌─────────────────────────────┐
│ cdk8s-nixos-vm-chart.ts     │
│ (TypeScript interface)      │
└────────────┬────────────────┘
             │ uses
             ├────────────────────────────┐
             │                            │
             ▼                            ▼
  ┌──────────────────┐       ┌───────────────────────────┐
  │ DataVolume       │       │ external-secret-rustdesk  │
  │ (pulls image)    │       │ (syncs password)          │
  └──────┬───────────┘       └─────────┬─────────────────┘
         │                             │
         └──────────┬──────────────────┘
                    │ both used by
                    ▼
             ┌──────────────┐
             │ VM Instance  │
             └──────────────┘
```

## Validation Workflow

### Build Time (NixOS Image)

1. **Module validation**: Nix type checker validates `nixos-rustdesk-module.nix` options
2. **Build validation**: `nix build .#nixos-kubevirt-image` succeeds
3. **Service validation**: Check systemd service exists in image

### Deployment Time (Kubernetes)

1. **TypeScript compilation**: `npx tsc --noEmit` validates `NixOsVmChartProps` interface
2. **Synthesis validation**: `npx ts-node main-v2.ts` generates valid YAML
3. **Sync wave ordering**: ArgoCD deploys in order:
   - ClusterSecretStore (wave -90)
   - ExternalSecret (wave -70)
   - DataVolume (wave -100)
   - VM (wave 0)
4. **Runtime validation**: VM boots with RustDesk service running within 2 minutes

### Runtime (VM Operation)

1. **Service status**: `systemctl status rustdesk` returns "active (running)"
2. **Headless mode**: `cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless` shows "Y"
3. **Port listening**: `ss -tlnp | grep 21116` shows LISTEN state
4. **Connection test**: RustDesk client can connect using ID and password from Secret

## Testing Contracts

### Unit Tests (Contract Validation)

```bash
# NixOS module: Nix evaluation
nix eval .#nixosConfigurations.base-image.config.services.rustdesk.enable
# Expected: true

# TypeScript interface: Type checking
npx tsc --noEmit cdk8s/charts/infra/nixos-vm-chart.ts
# Expected: no errors

# YAML schema: kubectl validation
kubectl apply --dry-run=client -f contracts/external-secret-rustdesk.yaml
# Expected: externalsecret.external-secrets.io/rustdesk-password created (dry run)
```

### Integration Tests (Contract Compliance)

```bash
# Test 1: Base image contains RustDesk service
nix-store -q --references ./result | grep rustdesk
# Expected: /nix/store/...-rustdesk-flutter-...

# Test 2: VM references correct base image
kubectl get datavolume nixos-dev-vm-rootdisk -o jsonpath='{.spec.source.http.url}'
# Expected: http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2

# Test 3: Secret synced from Azure Key Vault
kubectl get externalsecret rustdesk-password -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Test 4: VM uses Secret for password
kubectl get vm nixos-dev-vm -o yaml | grep -A 5 "secretKeyRef"
# Expected: name: rustdesk-password, key: password
```

### End-to-End Tests (User Scenarios)

```bash
# Test: User Story 1 - Deploy VM with Working RustDesk Service
# 1. Build base image
nix build .#nixos-kubevirt-image

# 2. Push to MinIO
mc cp ./result minio/images/nixos-kubevirt-v2.qcow2

# 3. Update chart and deploy
cd cdk8s && npx ts-node main-v2.ts
source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update

# 4. Verify VM boots with RustDesk running (within 2 minutes)
kubectl wait --for=condition=Ready vmi/nixos-dev-vm --timeout=2m
kubectl exec nixos-dev-vm -- systemctl status rustdesk
# Expected: active (running)

# 5. Test connection from RustDesk client
# (manual test with RustDesk client application)
```

## Breaking Changes

If you modify a contract, update the version:

- **MAJOR**: Incompatible changes (e.g., remove required option, change data type)
- **MINOR**: Add optional feature (e.g., new optional prop)
- **PATCH**: Clarification, documentation, non-functional changes

**Current Version**: 1.0.0 (initial implementation)

## Next Steps

1. Implement contracts in actual code:
   - Add `nixos-rustdesk-module.nix` to base image flake
   - Update `NixOsVmChartProps` interface in `nixos-vm-chart.ts`
   - Create `rustdesk-password` ExternalSecret in secrets chart

2. Validate contract compliance:
   - Run unit tests (Nix eval, TypeScript compile, kubectl dry-run)
   - Run integration tests (image build, VM deployment, service status)
   - Run E2E tests (full user scenarios from spec.md)

3. Document deviations (if any):
   - If implementation differs from contract, update contract first
   - Ensure all consumers are updated for contract changes
