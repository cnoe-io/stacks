# NixOS KubeVirt Desktop Docker Image

This directory contains resources for building a Docker image that serves NixOS qcow2 images for KubeVirt DataVolumes.

## Architecture

The Docker image combines:
1. **NixOS qcow2 Image**: Built from `/etc/nixos/configurations/kubevirt-desktop.nix` using `nixos-generate`
2. **nginx Web Server**: Alpine-based nginx to serve the qcow2 file over HTTP

The resulting image is consumed by KubeVirt's DataVolume import process via HTTP.

## Files

- `Dockerfile`: Multi-stage Docker build that packages the qcow2 with nginx
- `build-and-push.sh`: Automated build script for reproducible image creation
- `README.md`: This file

## Prerequisites

### On Build Machine (Hetzner NixOS Host)
- NixOS with `nixos-generate` installed
- Docker
- Access to `/etc/nixos/configurations/kubevirt-desktop.nix`
- Docker Hub credentials configured (`docker login`)

### NixOS Configuration
The qcow2 image is built from `/etc/nixos/configurations/kubevirt-desktop.nix` which includes:
- **Tailscale**: Zero-config VPN (`services.tailscale.enable = true`)
- **RustDesk**: Remote desktop server (installed in `environment.systemPackages`)
- **KDE Plasma 6**: Desktop environment (`services.desktopManager.plasma6.enable = true`)
- **cloud-init**: For runtime configuration injection
- **SSH**: OpenSSH server with key-based authentication

## Usage

### Quick Start

Build and push the latest version:

```bash
cd /home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop
./build-and-push.sh v1.1.0-tailscale
```

### Build Process Steps

The `build-and-push.sh` script automates:

1. **Build NixOS qcow2** (`nixos-generate`)
   - Duration: ~20-30 minutes (first build), ~3 minutes (cached)
   - Output: 11GB qcow2 file

2. **Prepare Docker Context**
   - Copies Dockerfile and qcow2 to temporary build directory

3. **Build Docker Image**
   - Creates nginx-based image with qcow2 at `/usr/share/nginx/html/nixos.qcow2`
   - Duration: ~1 minute

4. **Push to Docker Hub**
   - Pushes to `docker.io/vpittamp23/nixos-kubevirt-desktop:<tag>`
   - Duration: ~5-10 minutes (11GB upload)

### Manual Build

If you need to build manually:

```bash
# Step 1: Build NixOS qcow2
cd /etc/nixos
nixos-generate --format qcow \
  --configuration configurations/kubevirt-desktop.nix \
  --out-link /tmp/nixos-build

# Step 2: Prepare Docker build directory
mkdir -p /tmp/docker-build
cp /home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/Dockerfile /tmp/docker-build/
cp /tmp/nixos-build/nixos.qcow2 /tmp/docker-build/

# Step 3: Build Docker image
cd /tmp/docker-build
docker build -t vpittamp23/nixos-kubevirt-desktop:v1.1.0-tailscale .

# Step 4: Push to Docker Hub
docker push vpittamp23/nixos-kubevirt-desktop:v1.1.0-tailscale
```

## Integration with CDK8s

After building and pushing the image, update `config/applications.ts`:

```typescript
{
  name: 'nixos-image-server',
  namespace: 'default',
  chart: {
    type: 'NixOsImageServerChart',
    props: {
      image: 'vpittamp23/nixos-kubevirt-desktop:v1.1.0-tailscale'
    }
  },
  argocd: {
    syncWave: '-50',
    // ...
  }
}
```

Then synthesize and deploy:

```bash
cd /home/vpittamp/stacks/cdk8s
npx ts-node main-v2.ts
source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update
```

## Image Server Chart

The `NixOsImageServerChart` (`charts/apps/nixos-image-server-chart.ts`) expects:
- Docker image with nginx web server
- qcow2 file at `/usr/share/nginx/html/nixos.qcow2`
- HTTP server listening on port 80
- Readiness/liveness probes at `/nixos.qcow2`

## Deployment Workflow

1. **Build Image**: Run `build-and-push.sh` on Hetzner host
2. **Update Config**: Modify `applications.ts` with new image tag
3. **Synthesize**: Generate manifests with `npx ts-node main-v2.ts`
4. **Deploy**: Push to cluster with `cluster-update`
5. **Delete Resources**: Remove VM and DataVolume for fresh boot
   ```bash
   kubectl delete vm nixos-dev-vm -n default
   kubectl delete datavolume nixos-dev-datavolume -n default
   ```
6. **Verify**: Check ArgoCD auto-recreates resources with new image

## Troubleshooting

### Image Server Pod Fails with "no command specified"

**Cause**: Docker image doesn't have CMD/ENTRYPOINT (e.g., `FROM scratch` image)

**Solution**: Rebuild with this Dockerfile which uses `nginx:alpine` base

### DataVolume Import Fails

**Check**:
```bash
kubectl get pods -n default -l app=nixos-image-server
kubectl logs -n default deployment/nixos-image-server
kubectl describe datavolume nixos-dev-datavolume -n default
```

**Common Issues**:
- Image server pod not Running
- qcow2 file not at expected path
- Network policy blocking HTTP access

### VM Doesn't Have Tailscale/RustDesk

**Cause**: Old image cached by DataVolume

**Solution**: Delete both VM and DataVolume to force fresh import:
```bash
kubectl delete vm nixos-dev-vm -n default
kubectl delete datavolume nixos-dev-datavolume -n default
```

### Build Times Too Long

**Optimization**: Use Nix binary cache (Attic):
- Configure `/etc/nixos/configurations/kubevirt-desktop.nix` to use cache
- See `specs/003-implement-attic-minio/quickstart.md`
- Reduces build from 20 min → 3 min

## Versioning

Image tags follow this pattern:
- `v<major>.<minor>.<patch>-<feature>`
- Example: `v1.1.0-tailscale`

**Current Versions**:
- `v1.0.0-x11`: Initial release (no Tailscale, old X11)
- `v1.1.0-tailscale`: Tailscale + RustDesk + KDE Plasma 6

## CI/CD Integration (Future)

For automated builds, the `build-and-push.sh` script can be integrated into:
- GitHub Actions (on push to `/etc/nixos/configurations/`)
- GitLab CI
- Jenkins pipeline

Environment variables for customization:
- `DOCKER_REGISTRY`: Default `docker.io`
- `DOCKER_USERNAME`: Default `vpittamp23`
- `DOCKER_IMAGE`: Default `nixos-kubevirt-desktop`

## References

- NixOS Configuration: `/etc/nixos/configurations/kubevirt-desktop.nix`
- CDK8s Chart: `/home/vpittamp/stacks/cdk8s/charts/apps/nixos-image-server-chart.ts`
- nixos-generate: https://github.com/nix-community/nixos-generators
- KubeVirt DataVolumes: https://kubevirt.io/user-guide/operations/containerized_data_importer/
