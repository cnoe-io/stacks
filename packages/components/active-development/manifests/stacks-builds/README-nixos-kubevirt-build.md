# NixOS KubeVirt Tekton Build Notes

## What this pipeline builds

- `Pipeline/nixos-kubevirt-minimal-build`
- `Task/nixos-kubevirt-image-build-push`

The task clones `nixos-config`, builds a qcow2 flake output, then packages it into an nginx image for CDI/DataVolume import.

## KVM and builder compatibility

`make-disk-image` derivations request the `kvm` system feature. On Kind/Tekton workers without `/dev/kvm`, the task configures:

- `system-features = ... kvm`
- QEMU fallback via `accel=kvm:tcg` from Nix `vmTools`

This allows software-emulated image builds in CI, but they are slower than true KVM hosts.

For production throughput, prefer a dedicated KVM-capable builder node/pool.

## Wayland vs X11

- Default flake attr: `kubevirt-minimal-qcow2` (headless/minimal base)
- Wayland desktop attr: `kubevirt-sway-qcow2` (Sway/Wayland image)

Current recommended path is Wayland-first. Use `kubevirt-sway-qcow2` for GUI desktop workflows; keep X11-specific stacks out unless a workload explicitly requires them.

## Manual run examples

Minimal:

```yaml
params:
  - name: flake_attr
    value: kubevirt-minimal-qcow2
```

Wayland desktop:

```yaml
params:
  - name: flake_attr
    value: kubevirt-sway-qcow2
```

If you set `taskRunTemplate.serviceAccountName`, use an existing service account.
This component ships `image-build-bot` for manual image builds.
