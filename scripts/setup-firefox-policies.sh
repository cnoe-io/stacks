#!/usr/bin/env bash
# Setup Firefox policies for IDPBuilder development
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Firefox policy directories (both system and user)
FIREFOX_USER_POLICIES="$HOME/.mozilla/firefox/policies"
FIREFOX_SYSTEM_POLICIES="/usr/lib/firefox/distribution"

echo -e "${GREEN}======================================"
echo -e "Firefox Policy Setup for IDPBuilder"
echo -e "======================================${NC}"

# Create user policies directory
mkdir -p "$FIREFOX_USER_POLICIES"

# Create Firefox policy to trust local certificates and disable HSTS for development
cat > "$FIREFOX_USER_POLICIES/policies.json" <<'EOF'
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true,
      "Install": [
        "/home/vpittamp/.local/share/cluster-certs/idpbuilder.crt",
        "/home/vpittamp/stacks/certs/idpbuilder-ca.crt"
      ]
    },
    "DisableSecurityBypass": {
      "InvalidCertificate": false,
      "SafeBrowsing": false
    },
    "SecurityDevices": {
      "IDPBuilder Local Development": "/home/vpittamp/.local/share/cluster-certs/"
    },
    "Preferences": {
      "security.enterprise_roots.enabled": {
        "Value": true,
        "Status": "default"
      },
      "network.stricttransportsecurity.preloadlist": {
        "Value": false,
        "Status": "user"
      },
      "dom.security.https_only_mode": {
        "Value": false,
        "Status": "user"
      },
      "dom.security.https_only_mode_ever_enabled": {
        "Value": false,
        "Status": "user"
      }
    },
    "WebsiteFilter": {
      "Exceptions": [
        "https://*.cnoe.localtest.me:8443/*",
        "https://cnoe.localtest.me:8443/*"
      ]
    }
  }
}
EOF

echo "  ✓ Created Firefox user policies at $FIREFOX_USER_POLICIES/policies.json"

# Try to create system-wide policies if we have sudo
if command -v sudo >/dev/null 2>&1 && [ -d "/usr/lib/firefox" ]; then
    echo -e "${GREEN}Creating system-wide Firefox policies...${NC}"
    sudo mkdir -p "$FIREFOX_SYSTEM_POLICIES"
    sudo tee "$FIREFOX_SYSTEM_POLICIES/policies.json" > /dev/null <<'EOF'
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true
    },
    "DisableSecurityBypass": {
      "InvalidCertificate": false
    }
  }
}
EOF
    echo "  ✓ Created system-wide Firefox policies"
elif [ -d "/usr/lib64/firefox" ]; then
    # For systems with firefox in lib64
    FIREFOX_SYSTEM_POLICIES="/usr/lib64/firefox/distribution"
    echo -e "${GREEN}Creating system-wide Firefox policies (lib64)...${NC}"
    sudo mkdir -p "$FIREFOX_SYSTEM_POLICIES"
    sudo tee "$FIREFOX_SYSTEM_POLICIES/policies.json" > /dev/null <<'EOF'
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true
    },
    "DisableSecurityBypass": {
      "InvalidCertificate": false
    }
  }
}
EOF
    echo "  ✓ Created system-wide Firefox policies (lib64)"
fi

# Also create a user.js file for existing Firefox profiles
echo -e "${GREEN}Applying settings to Firefox profiles...${NC}"
for profile_dir in "$HOME"/.mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.dev-edition-default*; do
    if [[ -d "$profile_dir" ]]; then
        profile_name=$(basename "$profile_dir")
        cat > "$profile_dir/user.js" <<'EOF'
// IDPBuilder Development Settings
user_pref("security.enterprise_roots.enabled", true);
user_pref("network.stricttransportsecurity.preloadlist", false);
user_pref("dom.security.https_only_mode", false);
user_pref("dom.security.https_only_mode_ever_enabled", false);
user_pref("security.tls.version.min", 1);
user_pref("security.tls.version.max", 4);
EOF
        echo "  ✓ Applied settings to Firefox profile: $profile_name"
    fi
done

echo
echo -e "${GREEN}======================================"
echo -e "Firefox Policy Setup Complete!"
echo -e "======================================${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Restart Firefox for policies to take effect"
echo "  2. Run the certificate sync script: ~/stacks/scripts/sync-cluster-certificates.sh"
echo "  3. Access IDPBuilder services at https://*.cnoe.localtest.me:8443"
echo
echo -e "${YELLOW}Note:${NC} These policies reduce Firefox security for local development."
echo "      Only use this Firefox instance for development purposes."