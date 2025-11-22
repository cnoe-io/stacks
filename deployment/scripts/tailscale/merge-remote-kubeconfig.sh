#!/usr/bin/env bash
# Merge remote kubeconfig from 1Password into default kubeconfig
set -euo pipefail

ITEM_NAME="${1:-remote-kubeconfig}"
TEMP_FILE="/tmp/remote-kubeconfig-$$.yaml"

echo "Fetching '$ITEM_NAME' from 1Password..."
op document get "$ITEM_NAME" --out-file "$TEMP_FILE"

# Find online kind-operator from Tailscale
ONLINE_OPERATOR=$(tailscale status | grep -E '^[0-9.]+\s+kind-operator' | grep -v 'offline' | awk '{print $2}' | head -1)

if [[ -n "$ONLINE_OPERATOR" ]]; then
    # Extract current operator from kubeconfig
    CURRENT_OPERATOR=$(grep -oE 'kind-operator[^.]*' "$TEMP_FILE" | head -1)
    if [[ -n "$CURRENT_OPERATOR" && "$CURRENT_OPERATOR" != "$ONLINE_OPERATOR" ]]; then
        sed -i "s/${CURRENT_OPERATOR}/${ONLINE_OPERATOR}/g" "$TEMP_FILE"
        echo "Updated hostname: $CURRENT_OPERATOR -> $ONLINE_OPERATOR"
    fi
else
    echo "WARNING: No online kind-operator found in Tailscale"
    echo "Available operators:"
    tailscale status | grep -E 'kind-operator' | head -5
fi

echo "Merging into ~/.kube/config..."
KUBECONFIG="${HOME}/.kube/config:${TEMP_FILE}" kubectl config view --flatten > /tmp/merged-config-$$.yaml
mv /tmp/merged-config-$$.yaml ~/.kube/config

rm -f "$TEMP_FILE"

echo "Done. Available contexts:"
kubectl config get-contexts
