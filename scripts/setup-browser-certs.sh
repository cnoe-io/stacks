#!/usr/bin/env bash
# Certificate setup for Chromium - imports IDPBuilder CA into browser trust store
# This allows Chromium to trust *.cnoe.localtest.me certificates without bypassing security
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CERT_DIR="$HOME/.local/share/cluster-certs"
CHROMIUM_POLICIES_DIR="$HOME/.config/chromium/policies/managed"

echo -e "${GREEN}======================================"
echo -e "IDPBuilder Certificate Import for Chromium"
echo -e "======================================${NC}"

# Create directories
mkdir -p "${CERT_DIR}"
mkdir -p "${CHROMIUM_POLICIES_DIR}"

# Check if cluster is running
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Error: No Kubernetes cluster found${NC}"
    echo "Please create a cluster first with: cluster-deploy"
    exit 1
fi

# Extract IDPBuilder certificate
echo -e "${GREEN}Extracting IDPBuilder certificate...${NC}"
if kubectl get secret idpbuilder-cert -n ingress-nginx &>/dev/null; then
    kubectl get secret idpbuilder-cert -n ingress-nginx -o jsonpath='{.data.tls\.crt}' | base64 -d > "${CERT_DIR}/idpbuilder.crt"
    echo "  ✓ Certificate extracted"
elif kubectl get secret idpbuilder-cert -n default &>/dev/null; then
    kubectl get secret idpbuilder-cert -n default -o jsonpath='{.data.tls\.crt}' | base64 -d > "${CERT_DIR}/idpbuilder.crt"
    echo "  ✓ Certificate extracted"
else
    echo -e "${YELLOW}⚠️  Warning: IDPBuilder certificate not found${NC}"
fi

# Create a Chromium policy file for local certificates
echo -e "${GREEN}Creating Chromium policy for certificate acceptance...${NC}"
cat > "${CHROMIUM_POLICIES_DIR}/local-dev-certs.json" <<'EOF'
{
  "AutoSelectCertificateForUrls": [
    "{\"pattern\":\"https://[*.]cnoe.localtest.me\",\"filter\":{}}"
  ],
  "InsecureContentAllowedForUrls": [
    "https://*.cnoe.localtest.me:8443",
    "https://cnoe.localtest.me:8443"
  ],
  "CertificateTransparencyEnforcementDisabledForUrls": [
    "*.cnoe.localtest.me",
    "cnoe.localtest.me"
  ],
  "HSTSPolicyBypassList": [
    "*.cnoe.localtest.me",
    "cnoe.localtest.me"
  ]
}
EOF

# Function to run certutil with or without nix-shell
run_certutil() {
    if command -v certutil &>/dev/null; then
        certutil "$@"
        return $?
    elif command -v nix-shell &>/dev/null; then
        # Build the command as a string for nix-shell
        local cmd="certutil"
        for arg in "$@"; do
            # Escape single quotes and wrap argument
            arg="${arg//\'/\'\\\'\'}"
            cmd="$cmd '$arg'"
        done
        nix-shell -p nss_latest.tools --run "$cmd"
        return $?
    else
        return 1
    fi
}

# Import certificate to NSS database (used by Chromium/Firefox)
echo -e "${GREEN}Importing certificate to browser trust store...${NC}"
if [ -f "${CERT_DIR}/idpbuilder.crt" ]; then
    
    # Check if we can use certutil (certutil exits with 1 on --help, so check differently)
    if command -v certutil &>/dev/null || command -v nix-shell &>/dev/null; then
        echo "  Using certutil to import certificate..."
        
        # Create NSS database if it doesn't exist
        if [ ! -d "$HOME/.pki/nssdb" ]; then
            mkdir -p "$HOME/.pki/nssdb"
            run_certutil -N -d sql:$HOME/.pki/nssdb --empty-password
        fi
        
        # Remove old certificate if exists (clean up previous imports)
        run_certutil -D -n "IDPBuilder-CA" -d sql:$HOME/.pki/nssdb 2>/dev/null || true
        
        # Add new certificate with proper trust arguments for SSL
        # C = Trusted CA for issuing SSL server certificates
        # The empty fields (,,) mean not trusted for email or object signing
        run_certutil -A -n "IDPBuilder-CA" -t "C,," -d sql:$HOME/.pki/nssdb -i "${CERT_DIR}/idpbuilder.crt"
        echo "  ✓ Certificate imported to NSS database"
        echo "  ✓ Chromium will now trust *.cnoe.localtest.me certificates"
    else
        echo -e "${YELLOW}  ⚠️  certutil not found${NC}"
        echo -e "${YELLOW}     Please install nss-tools: nix-shell -p nss.tools${NC}"
        echo -e "${YELLOW}     Or add to system packages and rebuild${NC}"
    fi
else
    echo -e "${RED}  ❌ Certificate file not found at ${CERT_DIR}/idpbuilder.crt${NC}"
fi

# Only create wrapper script if certificate import failed
if ! command -v certutil &>/dev/null && ! command -v nix-shell &>/dev/null || [ ! -f "${CERT_DIR}/idpbuilder.crt" ]; then
    echo -e "${GREEN}Creating fallback Chromium wrapper script...${NC}"
    cat > "$HOME/.local/bin/chromium-dev" <<'EOF'
#!/usr/bin/env bash
# Chromium wrapper for local development - fallback when certificate import is not available
# This is less secure than proper certificate import but works without certutil

# Launch Chromium with minimal certificate bypass for local development
exec chromium \
  --ignore-certificate-errors \
  --allow-running-insecure-content \
  --user-data-dir="$HOME/.config/chromium-dev" \
  "$@"
EOF
    chmod +x "$HOME/.local/bin/chromium-dev"
    echo "  ✓ Fallback wrapper created (less secure, use only for development)"
else
    # Remove old wrapper if certificate import succeeded
    if [ -f "$HOME/.local/bin/chromium-dev" ]; then
        rm -f "$HOME/.local/bin/chromium-dev"
        echo -e "${GREEN}Removed old chromium-dev wrapper (no longer needed with certificate import)${NC}"
    fi
fi

# Remove old desktop launcher if it exists
if [ -f "$HOME/Desktop/chromium-dev.desktop" ]; then
    rm -f "$HOME/Desktop/chromium-dev.desktop"
    echo -e "${GREEN}Removed old desktop launcher${NC}"
fi

# Create an alias for easy terminal launch (only if wrapper was created)
if [ -f "$HOME/.local/bin/chromium-dev" ]; then
    if [ -w ~/.bashrc ] && ! grep -q "alias chromium-dev" ~/.bashrc 2>/dev/null; then
        echo "# Chromium development launcher" >> ~/.bashrc
        echo "alias chromium-dev='$HOME/.local/bin/chromium-dev'" >> ~/.bashrc
        echo "  ✓ Added chromium-dev alias to ~/.bashrc"
    elif grep -q "alias chromium-dev" ~/.bashrc 2>/dev/null; then
        echo "  ✓ chromium-dev alias already exists"
    fi
fi

echo ""
echo -e "${GREEN}======================================"
echo -e "Certificate Setup Complete!"
echo -e "======================================${NC}"
echo ""

if (command -v certutil &>/dev/null || command -v nix-shell &>/dev/null) && [ -f "${CERT_DIR}/idpbuilder.crt" ]; then
    echo -e "${BLUE}✅ Certificate successfully imported!${NC}"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  Just use regular Chromium - it will now trust IDPBuilder certificates!"
    echo "  $ chromium"
    echo ""
    echo -e "${GREEN}The following URLs will work without certificate warnings:${NC}"
    echo "  • https://argocd.cnoe.localtest.me:8443"
    echo "  • https://gitea.cnoe.localtest.me:8443"
    echo "  • https://backstage.cnoe.localtest.me:8443"
    echo "  • https://headlamp.cnoe.localtest.me:8443"
    echo "  • https://kargo.cnoe.localtest.me:8443"
    echo ""
    echo -e "${BLUE}Note:${NC} When the cluster is recreated, run this script again to update the certificate."
else
    echo -e "${YELLOW}⚠️  Certificate import was not completed${NC}"
    echo ""
    if ! command -v certutil &>/dev/null; then
        echo -e "${YELLOW}Missing certutil - to enable proper certificate trust:${NC}"
        echo "  1. Add nss.tools to your NixOS configuration"
        echo "  2. Rebuild: sudo nixos-rebuild switch"
        echo "  3. Run this script again"
        echo ""
        echo "Fallback: Use chromium-dev wrapper (less secure):"
        echo "  $ chromium-dev"
    fi
fi

echo ""
echo -e "${GREEN}To re-run this script after cluster recreation:${NC}"
echo "  $ ~/stacks/scripts/setup-browser-certs.sh"