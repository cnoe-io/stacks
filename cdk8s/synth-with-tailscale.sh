#!/usr/bin/env bash
# Synthesize CDK8s charts with Tailscale auth key from 1Password
set -e

echo "Retrieving Tailscale auth key from 1Password..."
TAILSCALE_VM_AUTH_KEY=$(op item get "Tailscale Auth Key" --fields credential --reveal 2>&1)

# Verify the auth key was retrieved (should start with tskey-)
if [[ ! "$TAILSCALE_VM_AUTH_KEY" =~ ^tskey- ]]; then
  echo "ERROR: Failed to retrieve Tailscale auth key from 1Password"
  echo "Output was: $TAILSCALE_VM_AUTH_KEY"
  echo ""
  echo "Please ensure:"
  echo "  1. 1Password CLI (op) is installed and authenticated"
  echo "  2. An item named 'Tailscale Auth Key' exists with a 'credential' field"
  echo "  3. Run 'op signin' if needed"
  exit 1
fi

export TAILSCALE_VM_AUTH_KEY
echo "Auth key retrieved: ${TAILSCALE_VM_AUTH_KEY:0:20}..."

npm run synth

echo ""
echo "Verifying auth key in manifest..."
if grep -q 'authkey="tskey-' dist/nixos-sway-vm/manifests/VirtualMachine.nixos-sway-vm.k8s.yaml; then
  echo "✓ Auth key successfully embedded in manifest"
  grep -o 'authkey="[^"]*"' dist/nixos-sway-vm/manifests/VirtualMachine.nixos-sway-vm.k8s.yaml | head -c 60
  echo "..."
else
  echo "ERROR: Auth key not found in manifest!"
  echo "The cloud-init will not have the auth key for automatic Tailscale login."
  exit 1
fi
