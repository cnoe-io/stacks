#!/usr/bin/env bash
#
# setup-github-app.sh - Create and configure GitHub App for CAIPE agents
#
# This script assists with creating a GitHub App using the manifest flow
# and stores the private key in Azure Key Vault.
#
# Prerequisites:
# - gh CLI authenticated (gh auth login)
# - az CLI authenticated (az login)
# - Access to Azure Key Vault
#
# Usage:
#   ./setup-github-app.sh --org <ORGANIZATION> --keyvault <KEYVAULT_NAME>
#   ./setup-github-app.sh --user --keyvault <KEYVAULT_NAME>
#
# References:
# - https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest
# - https://external-secrets.io/latest/api/generator/github/

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
GITHUB_ORG=""
USE_USER_ACCOUNT=false
KEYVAULT_NAME=""
APP_NAME="caipe-github-agent"
CALLBACK_URL="http://localhost:8080/callback"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create a GitHub App for CAIPE agents using the manifest flow.

Options:
    --org <ORG>           GitHub organization for the app
    --user                Create as a personal app (instead of org)
    --keyvault <NAME>     Azure Key Vault name to store private key
    --app-name <NAME>     GitHub App name (default: caipe-github-agent)
    -h, --help            Show this help message

Examples:
    # Create org app
    $(basename "$0") --org PittampalliOrg --keyvault keyvault-xyz

    # Create personal app
    $(basename "$0") --user --keyvault keyvault-xyz

EOF
    exit 1
}

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v gh &>/dev/null; then
        log_error "gh CLI not found. Install from https://cli.github.com/"
        exit 1
    fi

    if ! gh auth status &>/dev/null; then
        log_error "gh CLI not authenticated. Run: gh auth login"
        exit 1
    fi

    if ! command -v az &>/dev/null; then
        log_error "az CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi

    if ! az account show &>/dev/null; then
        log_error "az CLI not authenticated. Run: az login"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq not found. Install with: brew install jq / apt install jq"
        exit 1
    fi

    log_success "All prerequisites met"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --org)
                GITHUB_ORG="$2"
                shift 2
                ;;
            --user)
                USE_USER_ACCOUNT=true
                shift
                ;;
            --keyvault)
                KEYVAULT_NAME="$2"
                shift 2
                ;;
            --app-name)
                APP_NAME="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [[ -z "$KEYVAULT_NAME" ]]; then
        log_error "Key Vault name is required (--keyvault)"
        usage
    fi

    if [[ -z "$GITHUB_ORG" && "$USE_USER_ACCOUNT" != "true" ]]; then
        log_error "Either --org or --user is required"
        usage
    fi
}

create_manifest() {
    log_info "Creating GitHub App manifest..."

    # Define permissions needed for CAIPE GitHub agent
    # These are the minimum permissions for typical CI/CD and code operations
    cat > /tmp/github-app-manifest.json <<EOF
{
  "name": "${APP_NAME}",
  "description": "CAIPE AI Platform Engineering GitHub Agent - Short-lived token generation",
  "url": "https://github.com/cnoe-io/ai-platform-engineering",
  "hook_attributes": {
    "active": false
  },
  "redirect_url": "${CALLBACK_URL}",
  "callback_urls": ["${CALLBACK_URL}"],
  "public": false,
  "default_permissions": {
    "contents": "write",
    "issues": "write",
    "pull_requests": "write",
    "metadata": "read",
    "actions": "read",
    "workflows": "write",
    "statuses": "write",
    "checks": "write"
  },
  "default_events": []
}
EOF

    log_success "Manifest created at /tmp/github-app-manifest.json"
    log_info "Permissions configured:"
    echo "  - contents: write (read/write code)"
    echo "  - issues: write (manage issues)"
    echo "  - pull_requests: write (manage PRs)"
    echo "  - metadata: read (basic repo info)"
    echo "  - actions: read (view workflow runs)"
    echo "  - workflows: write (trigger workflows)"
    echo "  - statuses: write (set commit statuses)"
    echo "  - checks: write (create check runs)"
}

create_app_via_manifest() {
    log_info "GitHub App creation requires a web-based flow..."
    echo ""

    if [[ "$USE_USER_ACCOUNT" == "true" ]]; then
        SETTINGS_URL="https://github.com/settings/apps/new"
    else
        SETTINGS_URL="https://github.com/organizations/${GITHUB_ORG}/settings/apps/new"
    fi

    # Create HTML file for the manifest flow
    cat > /tmp/create-github-app.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Create GitHub App - ${APP_NAME}</title>
    <style>
        body { font-family: system-ui; max-width: 600px; margin: 50px auto; padding: 20px; }
        h1 { color: #24292f; }
        .manifest { background: #f6f8fa; padding: 15px; border-radius: 6px; margin: 20px 0; }
        pre { overflow-x: auto; }
        button { background: #2da44e; color: white; border: none; padding: 12px 24px;
                 font-size: 16px; border-radius: 6px; cursor: pointer; }
        button:hover { background: #2c974b; }
    </style>
</head>
<body>
    <h1>Create GitHub App: ${APP_NAME}</h1>
    <p>Click the button below to create the GitHub App with the pre-configured manifest.</p>

    <form action="${SETTINGS_URL}" method="post">
        <input type="hidden" name="manifest" value='$(cat /tmp/github-app-manifest.json | jq -c .)'>
        <button type="submit">Create GitHub App</button>
    </form>

    <div class="manifest">
        <h3>Manifest Preview:</h3>
        <pre>$(cat /tmp/github-app-manifest.json | jq .)</pre>
    </div>

    <h3>Next Steps:</h3>
    <ol>
        <li>Click "Create GitHub App" above</li>
        <li>Review the app settings on GitHub</li>
        <li>Click "Create GitHub App" on GitHub</li>
        <li>Copy the App ID shown after creation</li>
        <li>Generate and download the private key</li>
        <li>Install the app on your organization/repositories</li>
        <li>Note the Installation ID from the URL</li>
    </ol>
</body>
</html>
EOF

    log_info "Opening browser for GitHub App creation..."
    echo ""
    echo "A browser window will open. Please:"
    echo "  1. Click 'Create GitHub App'"
    echo "  2. Review settings and confirm on GitHub"
    echo "  3. Note the App ID after creation"
    echo "  4. Generate and download the private key (PEM file)"
    echo "  5. Install the app on your organization"
    echo "  6. Note the Installation ID from the install URL"
    echo ""

    # Try to open the HTML file
    if command -v xdg-open &>/dev/null; then
        xdg-open /tmp/create-github-app.html 2>/dev/null || true
    elif command -v open &>/dev/null; then
        open /tmp/create-github-app.html 2>/dev/null || true
    else
        log_warn "Could not open browser. Open this file manually: /tmp/create-github-app.html"
    fi

    echo ""
    read -p "Press Enter after you've created the app and downloaded the private key..."
}

collect_app_info() {
    echo ""
    log_info "Collecting GitHub App information..."
    echo ""

    read -p "Enter the GitHub App ID: " APP_ID
    read -p "Enter the Installation ID: " INSTALL_ID
    read -p "Enter path to private key file (.pem): " PRIVATE_KEY_PATH

    if [[ ! -f "$PRIVATE_KEY_PATH" ]]; then
        log_error "Private key file not found: $PRIVATE_KEY_PATH"
        exit 1
    fi

    # Validate the private key format
    if ! grep -q "BEGIN RSA PRIVATE KEY\|BEGIN PRIVATE KEY" "$PRIVATE_KEY_PATH"; then
        log_error "Invalid private key format. File should contain PEM-encoded private key."
        exit 1
    fi

    log_success "App ID: $APP_ID"
    log_success "Installation ID: $INSTALL_ID"
    log_success "Private key: $PRIVATE_KEY_PATH"
}

store_in_keyvault() {
    log_info "Storing private key in Azure Key Vault: $KEYVAULT_NAME"

    # Read the private key
    PRIVATE_KEY=$(cat "$PRIVATE_KEY_PATH")

    # Store in Key Vault
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "GITHUB-APP-PRIVATE-KEY" \
        --value "$PRIVATE_KEY" \
        --output none

    log_success "Private key stored as 'GITHUB-APP-PRIVATE-KEY' in $KEYVAULT_NAME"

    # Also store app metadata for reference
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "GITHUB-APP-ID" \
        --value "$APP_ID" \
        --output none

    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "GITHUB-APP-INSTALL-ID" \
        --value "$INSTALL_ID" \
        --output none

    log_success "App ID and Install ID stored in Key Vault"
}

verify_setup() {
    log_info "Verifying GitHub App setup..."

    # Generate a test token using gh api
    JWT_HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64 -w0 | tr '+/' '-_' | tr -d '=')

    CURRENT_TIME=$(date +%s)
    EXPIRY_TIME=$((CURRENT_TIME + 600))
    JWT_PAYLOAD=$(echo -n "{\"iat\":${CURRENT_TIME},\"exp\":${EXPIRY_TIME},\"iss\":\"${APP_ID}\"}" | base64 -w0 | tr '+/' '-_' | tr -d '=')

    # Sign with private key
    SIGNATURE=$(echo -n "${JWT_HEADER}.${JWT_PAYLOAD}" | openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" | base64 -w0 | tr '+/' '-_' | tr -d '=')

    JWT="${JWT_HEADER}.${JWT_PAYLOAD}.${SIGNATURE}"

    # Try to get installation token
    RESULT=$(curl -s -X POST \
        -H "Authorization: Bearer ${JWT}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app/installations/${INSTALL_ID}/access_tokens" 2>&1)

    if echo "$RESULT" | jq -e '.token' &>/dev/null; then
        log_success "GitHub App verification successful!"
        TOKEN=$(echo "$RESULT" | jq -r '.token')
        EXPIRES=$(echo "$RESULT" | jq -r '.expires_at')
        echo "  Token prefix: ${TOKEN:0:10}..."
        echo "  Expires: $EXPIRES"
    else
        log_warn "Verification returned unexpected response:"
        echo "$RESULT" | jq . 2>/dev/null || echo "$RESULT"
        log_warn "This might still work - the token generator will retry"
    fi
}

print_summary() {
    echo ""
    log_success "GitHub App setup complete!"
    echo ""
    echo "=============================================="
    echo "Configuration for applications.ts:"
    echo "=============================================="
    echo ""
    cat <<EOF
{
  name: 'github-token-generator',
  namespace: 'ai-platform-engineering',
  clusterType: 'kind',
  chart: {
    type: 'GithubTokenGeneratorChart',
    props: {
      namespace: 'ai-platform-engineering',
      appId: '${APP_ID}',
      installId: '${INSTALL_ID}',
      privateKeyVaultSecret: 'GITHUB-APP-PRIVATE-KEY',
      clusterSecretStoreName: 'azure-keyvault-store',
      // Optional: scope to specific repos
      // repositories: ['repo1', 'repo2'],
    },
  },
  argocd: {
    syncWave: '-70',
    labels: {
      'app.kubernetes.io/component': 'token-generator',
      'app.kubernetes.io/part-of': 'ai-platform-engineering',
      'app.kubernetes.io/name': 'github-token-generator'
    },
    syncPolicy: {
      automated: { prune: true, selfHeal: true }
    }
  }
},
EOF
    echo ""
    echo "=============================================="
    echo "Key Vault Secrets Created:"
    echo "=============================================="
    echo "  - GITHUB-APP-PRIVATE-KEY (PEM private key)"
    echo "  - GITHUB-APP-ID ($APP_ID)"
    echo "  - GITHUB-APP-INSTALL-ID ($INSTALL_ID)"
    echo ""
    echo "=============================================="
    echo "Next Steps:"
    echo "=============================================="
    echo "1. Add the config above to cdk8s/config/applications.ts"
    echo "2. Remove the static GITHUB_PAT from caipe-secrets if using generator"
    echo "3. Run: npm run synth"
    echo "4. Deploy with ArgoCD"
    echo ""
}

# Main
main() {
    echo ""
    echo "========================================"
    echo "  GitHub App Setup for CAIPE Agents"
    echo "========================================"
    echo ""

    parse_args "$@"
    check_prerequisites
    create_manifest
    create_app_via_manifest
    collect_app_info
    store_in_keyvault
    verify_setup
    print_summary
}

main "$@"
