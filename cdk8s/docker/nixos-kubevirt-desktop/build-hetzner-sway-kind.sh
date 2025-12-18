#!/usr/bin/env bash
set -euo pipefail

# Build a NixOS qcow2 image from github:vpittamp/nixos-config#hetzner-sway-qcow2,
# package it into the nginx image-server container, and load it into the Kind cluster.
#
# This is a workaround for environments where nixpkgs' cptofs/LKL-based image build hangs.
#
# Defaults are aligned with cdk8s/config/applications.ts:
# - image: nixos-hetzner-sway-qcow2:latest
# - Kind cluster name: ryzen

FLAKE_REF="${FLAKE_REF:-github:vpittamp/nixos-config}"
FLAKE_PKG="${FLAKE_PKG:-hetzner-sway-qcow2}"
INSTALLABLE="${FLAKE_REF}#${FLAKE_PKG}"

IMAGE_TAG="${IMAGE_TAG:-nixos-hetzner-sway-qcow2:latest}"
KIND_CLUSTER="${KIND_CLUSTER:-ryzen}"

DISK_SIZE_MIB="${DISK_SIZE_MIB:-51200}"  # 50GiB (MiB)
ROOT_LABEL="${ROOT_LABEL:-nixos}"

OUT_QCOW2="${OUT_QCOW2:-/tmp/nixos-hetzner-sway.qcow2}"
KEEP_BUILD_DIR="${KEEP_BUILD_DIR:-0}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

require nix
require jq
require docker
require kind
require qemu-img
require mkfs.ext4
require losetup
require sfdisk
require nixos-install

echo "=== Build hetzner-sway qcow2 for KubeVirt ==="
echo "Installable:   ${INSTALLABLE}"
echo "Image tag:     ${IMAGE_TAG}"
echo "Kind cluster:  ${KIND_CLUSTER}"
echo "Output qcow2:  ${OUT_QCOW2}"
echo ""

BUILD_DIR="$(mktemp -d -t nixos-hetzner-sway-build.XXXXXX)"
chmod 755 "${BUILD_DIR}"
ROOT_MNT="${BUILD_DIR}/mnt"
RAW_IMAGE="${BUILD_DIR}/nixos.raw"

LOOPDEV=""

cleanup() {
  set +e

  # Best-effort unmounts
  if mountpoint -q "${ROOT_MNT}"; then sudo umount "${ROOT_MNT}"; fi

  # Remove temporary /dev/vda symlinks if we created them
  for p in /dev/vda /dev/vda1; do
    if [ -L "${p}" ] && [ -n "${LOOPDEV}" ]; then
      target="$(readlink -f "${p}" 2>/dev/null || true)"
      if [ "${target}" = "${LOOPDEV}" ] || [ "${target}" = "${LOOPDEV}p1" ]; then
        sudo rm -f "${p}"
      fi
    fi
  done

  if [ -n "${LOOPDEV}" ]; then sudo losetup -d "${LOOPDEV}" >/dev/null 2>&1 || true; fi

  if [ "${KEEP_BUILD_DIR}" = "1" ]; then
    echo "Keeping build directory: ${BUILD_DIR}"
  else
    sudo rm -rf "${BUILD_DIR}"
  fi
}
trap cleanup EXIT

echo "Resolving system closure from ${INSTALLABLE}..."
DRV_JSON="$(nix derivation show "${INSTALLABLE}")"
DRV_KEY="$(printf '%s' "${DRV_JSON}" | jq -r 'keys[0]')"
PRE_VM="$(printf '%s' "${DRV_JSON}" | jq -r ".[\"${DRV_KEY}\"].env.preVM")"
SYSTEM_PATH="$(
  printf '%s' "${PRE_VM}" \
    | tr -s '[:space:]' '\n' \
    | awk 'p == "--system" { print; exit } { p = $0 }'
)"
SYSTEM_DRV="$(printf '%s' "${DRV_JSON}" | jq -r ".[\"${DRV_KEY}\"].inputDrvs | keys[] | select(test(\"-nixos-system-\"))" | head -n1 || true)"

if [ -z "${SYSTEM_PATH}" ]; then
  echo "ERROR: could not extract --system path from derivation preVM script" >&2
  exit 1
fi

echo "System closure: ${SYSTEM_PATH}"
if [ -n "${SYSTEM_DRV}" ] && [ ! -e "${SYSTEM_PATH}" ]; then
  SYSTEM_DRV_PATH="/nix/store/${SYSTEM_DRV}"
  echo "Realising system closure derivation (missing output): ${SYSTEM_DRV_PATH}"
  nix-store --realise "${SYSTEM_DRV_PATH}" >/dev/null
fi

echo ""
echo "Creating raw disk image (${DISK_SIZE_MIB}MiB) with a simple MBR layout..."
truncate -s "${DISK_SIZE_MIB}M" "${RAW_IMAGE}"

# Create a single bootable Linux partition starting at 1MiB.
# This avoids depending on nixpkgs' LKL/cptofs + avoids requiring parted/sgdisk on the host.
sudo sfdisk "${RAW_IMAGE}" >/dev/null <<'SFDISK'
label: dos
unit: sectors

1 : start=2048, type=83, bootable
SFDISK

# Set up loop device + partitions
LOOPDEV="$(sudo losetup --find --show --partscan "${RAW_IMAGE}")"
echo "Loop device: ${LOOPDEV}"

for i in {1..50}; do
  [ -b "${LOOPDEV}p1" ] && break
  sleep 0.1
done
if [ ! -b "${LOOPDEV}p1" ]; then
  echo "ERROR: loop partitions did not appear for ${LOOPDEV}" >&2
  exit 1
fi

echo "Formatting filesystems..."
sudo mkfs.ext4 -F -L "${ROOT_LABEL}" "${LOOPDEV}p1" >/dev/null

echo "Mounting target root at ${ROOT_MNT}..."
sudo mkdir -p "${ROOT_MNT}"
sudo mount "${LOOPDEV}p1" "${ROOT_MNT}"
sudo mkdir -p "${ROOT_MNT}/etc/nixos"

echo "Installing NixOS system into disk (this may take a while)..."

# Ensure we don't accidentally overwrite a real /dev/vda device (should not exist on typical NVMe hosts).
if [ -e /dev/vda ] && [ ! -L /dev/vda ]; then
  echo "ERROR: /dev/vda exists on host; refusing to create a temporary symlink for GRUB install." >&2
  exit 1
fi

sudo ln -sf "${LOOPDEV}" /dev/vda
sudo ln -sf "${LOOPDEV}p1" /dev/vda1

sudo HOME="${BUILD_DIR}/home" nixos-install \
  --root "${ROOT_MNT}" \
  --system "${SYSTEM_PATH}" \
  --no-root-passwd \
  --no-channel-copy

echo ""
echo "Converting raw image to qcow2: ${OUT_QCOW2}"
sudo umount "${ROOT_MNT}"
sudo losetup -d "${LOOPDEV}"
LOOPDEV=""

mkdir -p "$(dirname "${OUT_QCOW2}")"
qemu-img convert -f raw -O qcow2 -c "${RAW_IMAGE}" "${OUT_QCOW2}"
echo "qcow2 size: $(du -h "${OUT_QCOW2}" | awk '{print $1}')"

echo ""
echo "Building Docker image: ${IMAGE_TAG}"
DOCKER_CTX="${BUILD_DIR}/docker-build"
mkdir -p "${DOCKER_CTX}"
cp "$(dirname "${BASH_SOURCE[0]}")/Dockerfile" "${DOCKER_CTX}/Dockerfile"
cp "${OUT_QCOW2}" "${DOCKER_CTX}/nixos.qcow2"
docker build -t "${IMAGE_TAG}" "${DOCKER_CTX}"

echo ""
echo "Loading image into Kind cluster '${KIND_CLUSTER}'..."
kind load docker-image --name "${KIND_CLUSTER}" "${IMAGE_TAG}"

echo ""
echo "Done."
echo "Next:"
echo "  - Ensure cdk8s uses image: ${IMAGE_TAG}"
echo "    (set NIXOS_SWAY_IMAGE_SERVER_IMAGE='${IMAGE_TAG}' before cdk8s synth / idpbuilder create)"
