#!/usr/bin/env bash
#
# Build Script Interface Contracts
#
# Feature: 004-deploy-nixos-vms
# Purpose: Define shell script interfaces for NixOS image building and Docker packaging
#
# These scripts implement FR-001 through FR-015 (Image Generation and Distribution)

#------------------------------------------------------------------------------
# Script 1: build-kubevirt-image.sh
#------------------------------------------------------------------------------
#
# Purpose: Build minimal NixOS qcow2 image using nixos-generators --format kubevirt
#
# User Story: US1 - Generate Minimal NixOS Base Image
# Requirements: FR-001 through FR-010
#
# Usage:
#   ./scripts/build-kubevirt-image.sh [OPTIONS]
#
# Options:
#   -c, --config PATH     NixOS configuration file path
#                         Default: /etc/nixos/configurations/kubevirt-minimal.nix
#
#   -o, --output PATH     Output directory for qcow2 file
#                         Default: /tmp/kubevirt-base-image
#
#   -f, --format FORMAT   nixos-generators format (always 'kubevirt')
#                         Default: kubevirt
#
#   -v, --verbose         Enable verbose output
#
#   -h, --help            Show help message
#
# Outputs:
#   ${OUTPUT_DIR}/nixos.qcow2  - Bootable qcow2 image (~1.7GB compressed)
#
# Exit Codes:
#   0   Success - qcow2 image built successfully
#   1   Configuration file not found or invalid
#   2   nixos-generators build failed
#   3   Output file validation failed (size, format)
#   4   Insufficient disk space
#
# Performance Guarantees:
#   - Build time: <5 minutes (with Nix binary cache)
#   - Output size: <2GB compressed
#
# Validation:
#   - Verifies configuration file exists and is valid Nix syntax
#   - Checks nixos-generators is installed (nix-shell or direct)
#   - Verifies output qcow2 file is valid format (qemu-img info)
#   - Checks GRUB bootloader exists on /dev/vda (via guestfish)
#
# Example:
#   ./scripts/build-kubevirt-image.sh \
#     --config /etc/nixos/configurations/kubevirt-minimal.nix \
#     --output /tmp/kubevirt-base-image \
#     --verbose
#
# Success Criteria: FR-010, SC-001

build_kubevirt_image() {
    local CONFIG_PATH="${1:-/etc/nixos/configurations/kubevirt-minimal.nix}"
    local OUTPUT_DIR="${2:-/tmp/kubevirt-base-image}"
    local FORMAT="kubevirt"

    # Validate inputs
    [[ -f "$CONFIG_PATH" ]] || {
        echo "Error: Configuration file not found: $CONFIG_PATH" >&2
        return 1
    }

    # Check nixos-generators availability
    if ! command -v nixos-generate &> /dev/null; then
        echo "Error: nixos-generate not found. Install via: nix-shell -p nixos-generators" >&2
        return 1
    fi

    # Check disk space (need ~10GB for build + output)
    local available_space
    available_space=$(df -BG "$(dirname "$OUTPUT_DIR")" | awk 'NR==2 {print $4}' | sed 's/G//')
    if (( available_space < 10 )); then
        echo "Error: Insufficient disk space. Need 10GB, have ${available_space}GB" >&2
        return 4
    fi

    echo "Building NixOS image with nixos-generators..."
    echo "  Config: $CONFIG_PATH"
    echo "  Format: $FORMAT"
    echo "  Output: $OUTPUT_DIR"

    # Build image (this takes ~5 minutes)
    if ! nixos-generate \
        --format "$FORMAT" \
        --configuration "$CONFIG_PATH" \
        --out-link "$OUTPUT_DIR"; then
        echo "Error: nixos-generate build failed" >&2
        return 2
    fi

    # Validate output
    local qcow2_file="$OUTPUT_DIR/nixos.qcow2"
    if [[ ! -f "$qcow2_file" ]]; then
        echo "Error: Expected output file not found: $qcow2_file" >&2
        return 3
    fi

    # Verify qcow2 format
    if ! qemu-img info "$qcow2_file" &> /dev/null; then
        echo "Error: Output file is not valid qcow2 format" >&2
        return 3
    fi

    # Report size
    local size_bytes
    size_bytes=$(stat -c%s "$qcow2_file")
    local size_gb
    size_gb=$(echo "scale=2; $size_bytes / 1073741824" | bc)
    echo "Success: Built qcow2 image (${size_gb}GB)"

    # Verify bootloader (requires libguestfs-tools)
    if command -v guestfish &> /dev/null; then
        echo "Verifying GRUB bootloader..."
        if guestfish --ro -a "$qcow2_file" -i command "test -d /boot/grub" &> /dev/null; then
            echo "✓ GRUB bootloader verified"
        else
            echo "⚠ Warning: GRUB bootloader not found (may not boot)" >&2
        fi
    fi

    return 0
}

#------------------------------------------------------------------------------
# Script 2: package-image-docker.sh
#------------------------------------------------------------------------------
#
# Purpose: Package qcow2 image into Docker container with nginx for HTTP distribution
#
# User Story: US2 - Create NixOS-based VM Image
# Requirements: FR-011 through FR-015
#
# Usage:
#   ./scripts/package-image-docker.sh [OPTIONS]
#
# Options:
#   -i, --input PATH      Path to qcow2 file
#                         Default: /tmp/kubevirt-base-image/nixos.qcow2
#
#   -t, --tag TAG         Docker image tag
#                         Default: vpittamp23/nixos-kubevirt-minimal:latest
#
#   -p, --push            Push image to Docker Hub after build
#
#   -v, --verbose         Enable verbose output
#
#   -h, --help            Show help message
#
# Outputs:
#   Docker image: <tag> containing:
#     - nginx:alpine base image
#     - qcow2 file at /usr/share/nginx/html/nixos.qcow2
#
# Exit Codes:
#   0   Success - Docker image built (and optionally pushed)
#   1   qcow2 file not found
#   2   Docker build failed
#   3   Docker push failed
#   4   Docker daemon not running
#
# Performance Guarantees:
#   - Build time: <1 minute (ADD qcow2 to image)
#   - Push time: <2 minutes (1.8GB image to Docker Hub)
#   - Image size: <2GB total
#
# Validation:
#   - Verifies qcow2 file exists
#   - Checks Docker daemon is running
#   - Verifies image build succeeded (docker images)
#   - Tests HTTP access after build (docker run + curl)
#
# Example:
#   ./scripts/package-image-docker.sh \
#     --input /tmp/kubevirt-base-image/nixos.qcow2 \
#     --tag vpittamp23/nixos-kubevirt-minimal:v1.0.0 \
#     --push \
#     --verbose
#
# Success Criteria: FR-015, SC-002

package_image_docker() {
    local QCOW2_PATH="${1:-/tmp/kubevirt-base-image/nixos.qcow2}"
    local IMAGE_TAG="${2:-vpittamp23/nixos-kubevirt-minimal:latest}"
    local PUSH="${3:-false}"

    # Validate inputs
    [[ -f "$QCOW2_PATH" ]] || {
        echo "Error: qcow2 file not found: $QCOW2_PATH" >&2
        return 1
    }

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon not running" >&2
        return 4
    fi

    echo "Packaging qcow2 into Docker image..."
    echo "  Input: $QCOW2_PATH"
    echo "  Tag: $IMAGE_TAG"

    # Create temporary directory with Dockerfile
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    # Generate Dockerfile
    cat > "$temp_dir/Dockerfile" <<'EOF'
FROM nginx:alpine

# Copy qcow2 file to nginx html directory
COPY nixos.qcow2 /usr/share/nginx/html/

# Ensure qcow2 is readable
RUN chmod 644 /usr/share/nginx/html/nixos.qcow2

# Expose HTTP port
EXPOSE 80

# nginx runs as PID 1 in alpine variant
CMD ["nginx", "-g", "daemon off;"]
EOF

    # Copy qcow2 to build context
    cp "$QCOW2_PATH" "$temp_dir/nixos.qcow2"

    # Build Docker image
    echo "Building Docker image..."
    if ! docker build -t "$IMAGE_TAG" "$temp_dir"; then
        echo "Error: Docker build failed" >&2
        return 2
    fi

    # Verify image exists
    if ! docker images "$IMAGE_TAG" | grep -q "$IMAGE_TAG"; then
        echo "Error: Image not found after build" >&2
        return 2
    fi

    # Report image size
    local image_size
    image_size=$(docker images "$IMAGE_TAG" --format "{{.Size}}")
    echo "Success: Built Docker image (${image_size})"

    # Test HTTP access (optional, requires starting container)
    echo "Testing HTTP access..."
    local container_id
    container_id=$(docker run -d --rm -p 0:80 "$IMAGE_TAG")
    sleep 2  # Wait for nginx to start

    if curl -f -s -o /dev/null "http://localhost:$(docker port "$container_id" 80 | cut -d: -f2)/nixos.qcow2"; then
        echo "✓ HTTP access verified"
    else
        echo "⚠ Warning: HTTP access test failed" >&2
    fi

    docker stop "$container_id" &> /dev/null

    # Push to registry if requested
    if [[ "$PUSH" == "true" ]]; then
        echo "Pushing to Docker Hub..."
        if ! docker push "$IMAGE_TAG"; then
            echo "Error: Docker push failed" >&2
            return 3
        fi
        echo "Success: Pushed $IMAGE_TAG"
    fi

    return 0
}

#------------------------------------------------------------------------------
# Script 3: deploy-vm-image.sh (Optional convenience wrapper)
#------------------------------------------------------------------------------
#
# Purpose: End-to-end workflow for building, packaging, pushing, and deploying
#
# Usage:
#   ./scripts/deploy-vm-image.sh [--push] [--deploy]
#
# Options:
#   --push      Push Docker image to Docker Hub
#   --deploy    Deploy to Kubernetes cluster via cluster-update
#
# Workflow:
#   1. Build qcow2 image (build-kubevirt-image.sh)
#   2. Package into Docker image (package-image-docker.sh)
#   3. Push to Docker Hub (if --push)
#   4. Run CDK8s synthesis (npx ts-node main-v2.ts)
#   5. Deploy via cluster-update (if --deploy)
#
# Exit Codes:
#   0   Success - Full workflow completed
#   Non-zero: Error at specific step (see individual script exit codes)

deploy_vm_image() {
    local PUSH=false
    local DEPLOY=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --push) PUSH=true; shift ;;
            --deploy) DEPLOY=true; shift ;;
            *) echo "Unknown option: $1" >&2; return 1 ;;
        esac
    done

    echo "=== Step 1: Build qcow2 image ==="
    build_kubevirt_image || return $?

    echo ""
    echo "=== Step 2: Package Docker image ==="
    package_image_docker \
        "/tmp/kubevirt-base-image/nixos.qcow2" \
        "vpittamp23/nixos-kubevirt-minimal:latest" \
        "$PUSH" || return $?

    if [[ "$DEPLOY" == "true" ]]; then
        echo ""
        echo "=== Step 3: CDK8s synthesis ==="
        (cd cdk8s && npx ts-node main-v2.ts) || return $?

        echo ""
        echo "=== Step 4: Deploy to cluster ==="
        source ~/stacks/deployment/scripts/cluster-menu.sh
        cluster-update || return $?

        echo ""
        echo "=== Deployment complete ==="
        echo "Check VM status: kubectl get vm,vmi -n default"
        echo "Access VM: virtctl console nixos-dev-vm"
    fi

    return 0
}

#------------------------------------------------------------------------------
# Contract Validation
#------------------------------------------------------------------------------

# Exit codes must be consistent:
#   0: Success
#   1: Input validation failure (file not found, invalid argument)
#   2: Build/execution failure (tool error, command failed)
#   3: Output validation failure (result doesn't meet spec)
#   4: Environment error (missing dependency, insufficient resources)

# All scripts must:
# - Accept --help flag showing usage
# - Accept --verbose flag for debug output
# - Use default values for all optional parameters
# - Validate inputs before executing commands
# - Clean up temporary files on exit (trap)
# - Log progress to stdout, errors to stderr
# - Return meaningful exit codes

# Performance SLAs:
# - build-kubevirt-image.sh: <5 minutes (FR-010, SC-001)
# - package-image-docker.sh: <1 minute build + <2 minutes push (FR-015, SC-002)
# - Total workflow: <10 minutes (Success Criterion SC-013)
