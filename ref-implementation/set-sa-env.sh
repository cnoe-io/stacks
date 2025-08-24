#!/bin/bash
# Environment setup for Service Account keys and Azure Workload Identity

# Get the absolute paths for the SA keys
export SERVICE_ACCOUNT_KEY_FILE="/home/vpittamp/stacks/ref-implementation/keys/sa.pub"
export SERVICE_ACCOUNT_SIGNING_KEY_FILE="/home/vpittamp/stacks/ref-implementation/keys/sa.key"

# Azure Workload Identity configuration
export SERVICE_ACCOUNT_ISSUER="https://oidcissuer65846b7df97b.z13.web.core.windows.net/"

# Verify files exist
if [ ! -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
    echo "ERROR: Service account public key not found at $SERVICE_ACCOUNT_KEY_FILE"
    exit 1
fi

if [ ! -f "$SERVICE_ACCOUNT_SIGNING_KEY_FILE" ]; then
    echo "ERROR: Service account private key not found at $SERVICE_ACCOUNT_SIGNING_KEY_FILE"
    exit 1
fi

echo "Service Account environment variables set:"
echo "  SERVICE_ACCOUNT_KEY_FILE=$SERVICE_ACCOUNT_KEY_FILE"
echo "  SERVICE_ACCOUNT_SIGNING_KEY_FILE=$SERVICE_ACCOUNT_SIGNING_KEY_FILE"
echo "  SERVICE_ACCOUNT_ISSUER=$SERVICE_ACCOUNT_ISSUER"