#!/usr/bin/env bash
# Certificate setup for browsers - imports gitops CA into Firefox and Chromium trust stores
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CERT_DIR="$HOME/.local/share/cluster-certs"
CHROMIUM_POLICIES_DIR="$HOME/.config/chromium/policies/managed"
CERT_SOURCE=""
SKIP_CLUSTER_CHECK=false

usage() {
    cat <<'HELP'
Usage: setup-browser-certs.sh [--cert-file PATH] [--no-cluster-check]

Options:
  --cert-file PATH       Import certificate from PATH instead of querying the cluster
  --no-cluster-check     Skip verifying that kubectl can reach the cluster
  -h, --help             Show this help message
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cert-file)
            CERT_SOURCE="$2"
            shift 2
            ;;
        --no-cluster-check)
            SKIP_CLUSTER_CHECK=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

echo -e "${GREEN}======================================"
echo -e "gitops Certificate Import for Browsers"
echo -e "======================================${NC}"

mkdir -p "$CERT_DIR" "$CHROMIUM_POLICIES_DIR"

if [[ -n "$CERT_SOURCE" ]]; then
    if [[ ! -f "$CERT_SOURCE" ]]; then
        echo -e "${RED}❌ Provided certificate file not found: $CERT_SOURCE${NC}"
        exit 1
    fi
    cp "$CERT_SOURCE" "$CERT_DIR/gitops.crt"
    echo "  ✓ Certificate copied from $CERT_SOURCE"
else
    if ! $SKIP_CLUSTER_CHECK && ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}❌ Error: No Kubernetes cluster found${NC}"
        echo "Please create a cluster first with: cluster-deploy"
        exit 1
    fi

    echo -e "${GREEN}Extracting gitops certificate...${NC}"
    if kubectl get secret gitops-cert -n ingress-nginx &>/dev/null; then
        kubectl get secret gitops-cert -n ingress-nginx -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT_DIR/gitops.crt"
        echo "  ✓ Certificate extracted"
    elif kubectl get secret gitops-cert -n default &>/dev/null; then
        kubectl get secret gitops-cert -n default -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT_DIR/gitops.crt"
        echo "  ✓ Certificate extracted"
    else
        echo -e "${YELLOW}⚠️  Warning: gitops certificate not found${NC}"
    fi
fi

echo -e "${GREEN}Creating Chromium policy for certificate acceptance...${NC}"
cat > "$CHROMIUM_POLICIES_DIR/local-dev-certs.json" <<'POLICY'
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
POLICY

run_certutil() {
    certutil "$@"
}

echo -e "${GREEN}Importing certificate to browser trust stores...${NC}"
if [[ -f "$CERT_DIR/gitops.crt" ]]; then
    if command -v certutil &>/dev/null; then
        # Import for Chromium (uses shared NSS database)
        echo "  Importing to Chromium NSS database..."
        if [[ ! -d "$HOME/.pki/nssdb" ]]; then
            mkdir -p "$HOME/.pki/nssdb"
            run_certutil -N -d sql:$HOME/.pki/nssdb --empty-password
        fi
        run_certutil -D -n "gitops-CA" -d sql:$HOME/.pki/nssdb 2>/dev/null || true
        run_certutil -A -n "gitops-CA" -t "C,," -d sql:$HOME/.pki/nssdb -i "$CERT_DIR/gitops.crt"
        echo "  ✓ Certificate imported to Chromium NSS database"

        # Import for Firefox (each profile has its own cert database)
        echo "  Importing to Firefox profiles..."
        FIREFOX_IMPORTED=false
        for profile_dir in "$HOME"/.mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.dev-edition-default*; do
            if [[ -d "$profile_dir" ]]; then
                profile_name=$(basename "$profile_dir")
                echo "    Processing Firefox profile: $profile_name"
                # Remove old certificate if exists
                run_certutil -D -n "gitops-CA" -d sql:"$profile_dir" 2>/dev/null || true
                # Add new certificate
                run_certutil -A -n "gitops-CA" -t "TC,C,C" -d sql:"$profile_dir" -i "$CERT_DIR/gitops.crt"
                echo "    ✓ Certificate imported to Firefox profile: $profile_name"
                FIREFOX_IMPORTED=true
            fi
        done

        if [[ "$FIREFOX_IMPORTED" == false ]]; then
            echo -e "${YELLOW}  ⚠️  No Firefox profiles found${NC}"
            echo -e "${YELLOW}     Start Firefox once to create a profile, then run this script again${NC}"
        else
            echo "  ✓ Firefox will now trust *.cnoe.localtest.me certificates"
        fi

        echo "  ✓ Browsers will now trust *.cnoe.localtest.me certificates"
    else
        echo -e "${YELLOW}  ⚠️  certutil not found${NC}"
        echo -e "${YELLOW}     Please install the nss tools package to provide certutil${NC}"
    fi
else
    echo -e "${RED}  ❌ Certificate file not found at ${CERT_DIR}/gitops.crt${NC}"
fi

NEED_WRAPPER=false
if ! command -v certutil &>/dev/null; then
    NEED_WRAPPER=true
fi
if [[ ! -f "$CERT_DIR/gitops.crt" ]]; then
    NEED_WRAPPER=true
fi

if [[ "$NEED_WRAPPER" == true ]]; then
    echo -e "${GREEN}Creating fallback Chromium wrapper script...${NC}"
    cat > "$HOME/.local/bin/chromium-dev" <<'EOFWRAP'
#!/usr/bin/env bash
exec chromium \
  --ignore-certificate-errors \
  --allow-running-insecure-content \
  --user-data-dir="$HOME/.config/chromium-dev" \
  "$@"
EOFWRAP
    chmod +x "$HOME/.local/bin/chromium-dev"
    echo "  ✓ Fallback wrapper created (less secure, use only for development)"
else
    if [[ -f "$HOME/.local/bin/chromium-dev" ]]; then
        rm -f "$HOME/.local/bin/chromium-dev"
        echo -e "${GREEN}Removed old chromium-dev wrapper (no longer needed with certificate import)${NC}"
    fi
fi

if [[ -f "$HOME/Desktop/chromium-dev.desktop" ]]; then
    rm -f "$HOME/Desktop/chromium-dev.desktop"
    echo -e "${GREEN}Removed old desktop launcher${NC}"
fi

if [[ -f "$HOME/.local/bin/chromium-dev" ]]; then
    if [[ -w "$HOME/.bashrc" ]] && ! grep -q "alias chromium-dev" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo "# Chromium development launcher"
            echo "alias chromium-dev='$HOME/.local/bin/chromium-dev'"
        } >> "$HOME/.bashrc"
        echo "  ✓ Added chromium-dev alias to ~/.bashrc"
    elif grep -q "alias chromium-dev" "$HOME/.bashrc" 2>/dev/null; then
        echo "  ✓ chromium-dev alias already exists"
    fi
fi

echo
echo -e "${GREEN}======================================"
echo -e "Certificate Setup Complete!"
echo -e "======================================${NC}"
echo

if command -v certutil &>/dev/null && [[ -f "$CERT_DIR/gitops.crt" ]]; then
    echo -e "${BLUE}✅ Certificate successfully imported!${NC}"
    echo
    echo -e "${BLUE}Usage:${NC}"
    echo "  Your browsers will now trust gitops certificates!"
    echo "  $ firefox       # Use Firefox as your default browser"
    echo "  $ chromium      # Or use Chromium"
    echo
    echo -e "${BLUE}Access your services:${NC}"
    echo "  • ArgoCD:     https://argocd.cnoe.localtest.me:8443"
    echo "  • Gitea:      https://gitea.cnoe.localtest.me:8443"
    echo "  • Headlamp:   https://headlamp.cnoe.localtest.me:8443"
    echo "  • Keycloak:   https://cnoe.localtest.me:8443"
else
    echo -e "${YELLOW}⚠️  Certificate import was not completed${NC}"
fi
