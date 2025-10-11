#!/usr/bin/env bash
set -e

# Synthesize CDK8s manifests with secrets loaded from 1Password
# This script loads SSH_PUBLIC_KEY from 1Password and runs synthesis

cd "$(dirname "$0")"

# Load SSH public key from 1Password
export SSH_PUBLIC_KEY=$(op read "op://Employee/k8s_ed_test/public key")

echo "✓ Loaded SSH key from 1Password: ${SSH_PUBLIC_KEY:0:50}..."

# Run synthesis
npx ts-node main-v2.ts
