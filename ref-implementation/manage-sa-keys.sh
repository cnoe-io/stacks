#!/usr/bin/env bash
# Service Account Key Management Script
# Generates, validates, and manages SA keys for Azure Workload Identity

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/keys"

function show_help() {
    echo -e "${BLUE}Service Account Key Management${NC}"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  generate    Generate new SA keys"
    echo "  validate    Validate existing keys"
    echo "  backup      Backup current keys"
    echo "  restore     Restore keys from backup"
    echo "  info        Show key information"
    echo "  jwks        Generate JWKS from public key"
    echo ""
    echo "Key locations:"
    echo "  Keys: ${KEYS_DIR}"
    echo "  Backup: ${KEYS_DIR}/backup/"
}

function generate_keys() {
    echo -e "${GREEN}Generating new service account keys...${NC}"
    
    # Create keys directory
    mkdir -p "${KEYS_DIR}"
    
    # Backup existing keys if they exist
    if [ -f "${KEYS_DIR}/sa.key" ] || [ -f "${KEYS_DIR}/sa.pub" ]; then
        echo -e "${YELLOW}Backing up existing keys...${NC}"
        backup_keys
    fi
    
    # Generate new RSA key pair
    openssl genrsa -out "${KEYS_DIR}/sa.key" 2048
    openssl rsa -in "${KEYS_DIR}/sa.key" -pubout -out "${KEYS_DIR}/sa.pub"
    
    # Set secure permissions
    chmod 600 "${KEYS_DIR}/sa.key"
    chmod 644 "${KEYS_DIR}/sa.pub"
    
    echo -e "${GREEN}✓ Keys generated successfully${NC}"
    echo "  Private key: ${KEYS_DIR}/sa.key"
    echo "  Public key:  ${KEYS_DIR}/sa.pub"
}

function validate_keys() {
    echo -e "${GREEN}Validating service account keys...${NC}"
    
    if [ ! -f "${KEYS_DIR}/sa.key" ] || [ ! -f "${KEYS_DIR}/sa.pub" ]; then
        echo -e "${RED}✗ Keys not found in ${KEYS_DIR}${NC}"
        return 1
    fi
    
    # Check key format
    if ! openssl rsa -in "${KEYS_DIR}/sa.key" -check -noout 2>/dev/null; then
        echo -e "${RED}✗ Invalid private key format${NC}"
        return 1
    fi
    
    if ! openssl rsa -pubin -in "${KEYS_DIR}/sa.pub" -noout 2>/dev/null; then
        echo -e "${RED}✗ Invalid public key format${NC}"
        return 1
    fi
    
    # Verify key pair matches
    PRIV_MODULUS=$(openssl rsa -in "${KEYS_DIR}/sa.key" -noout -modulus | md5sum)
    PUB_MODULUS=$(openssl rsa -pubin -in "${KEYS_DIR}/sa.pub" -noout -modulus | md5sum)
    
    if [ "$PRIV_MODULUS" != "$PUB_MODULUS" ]; then
        echo -e "${RED}✗ Key pair mismatch - public and private keys don't match${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Keys are valid${NC}"
    echo "  Key size: $(openssl rsa -in ${KEYS_DIR}/sa.key -text -noout | grep 'Private-Key:' | awk '{print $2}')"
    echo "  Key type: RSA"
}

function backup_keys() {
    BACKUP_DIR="${KEYS_DIR}/backup/$(date +%Y%m%d_%H%M%S)"
    
    echo -e "${GREEN}Backing up keys to ${BACKUP_DIR}...${NC}"
    mkdir -p "${BACKUP_DIR}"
    
    if [ -f "${KEYS_DIR}/sa.key" ]; then
        cp "${KEYS_DIR}/sa.key" "${BACKUP_DIR}/sa.key"
        chmod 600 "${BACKUP_DIR}/sa.key"
    fi
    
    if [ -f "${KEYS_DIR}/sa.pub" ]; then
        cp "${KEYS_DIR}/sa.pub" "${BACKUP_DIR}/sa.pub"
        chmod 644 "${BACKUP_DIR}/sa.pub"
    fi
    
    echo -e "${GREEN}✓ Keys backed up to ${BACKUP_DIR}${NC}"
}

function restore_keys() {
    echo -e "${GREEN}Available backups:${NC}"
    
    if [ ! -d "${KEYS_DIR}/backup" ]; then
        echo -e "${YELLOW}No backups found${NC}"
        return 1
    fi
    
    # List available backups
    BACKUPS=($(ls -1d ${KEYS_DIR}/backup/*/ 2>/dev/null | xargs -n1 basename))
    
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No backups found${NC}"
        return 1
    fi
    
    for i in "${!BACKUPS[@]}"; do
        echo "  $((i+1)). ${BACKUPS[$i]}"
    done
    
    echo ""
    read -p "Select backup to restore (1-${#BACKUPS[@]}): " selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#BACKUPS[@]} ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    SELECTED_BACKUP="${BACKUPS[$((selection-1))]}"
    BACKUP_PATH="${KEYS_DIR}/backup/${SELECTED_BACKUP}"
    
    echo -e "${GREEN}Restoring from ${SELECTED_BACKUP}...${NC}"
    
    # Backup current keys before restoring
    if [ -f "${KEYS_DIR}/sa.key" ] || [ -f "${KEYS_DIR}/sa.pub" ]; then
        backup_keys
    fi
    
    # Restore keys
    cp "${BACKUP_PATH}/sa.key" "${KEYS_DIR}/sa.key"
    cp "${BACKUP_PATH}/sa.pub" "${KEYS_DIR}/sa.pub"
    chmod 600 "${KEYS_DIR}/sa.key"
    chmod 644 "${KEYS_DIR}/sa.pub"
    
    echo -e "${GREEN}✓ Keys restored successfully${NC}"
}

function show_info() {
    echo -e "${GREEN}Service Account Key Information${NC}"
    echo ""
    
    if [ ! -f "${KEYS_DIR}/sa.key" ] || [ ! -f "${KEYS_DIR}/sa.pub" ]; then
        echo -e "${YELLOW}No keys found in ${KEYS_DIR}${NC}"
        echo "Run '$0 generate' to create new keys"
        return 1
    fi
    
    echo -e "${BLUE}Key Location:${NC}"
    echo "  Directory: ${KEYS_DIR}"
    echo "  Private: sa.key"
    echo "  Public: sa.pub"
    echo ""
    
    echo -e "${BLUE}Key Details:${NC}"
    # Get key info
    KEY_INFO=$(openssl rsa -in "${KEYS_DIR}/sa.key" -text -noout 2>/dev/null | head -5)
    echo "$KEY_INFO" | while read line; do echo "  $line"; done
    echo ""
    
    echo -e "${BLUE}Public Key Hash:${NC}"
    echo "  SHA256: $(openssl rsa -pubin -in ${KEYS_DIR}/sa.pub -outform DER 2>/dev/null | openssl dgst -sha256 | awk '{print $2}')"
    echo ""
    
    echo -e "${BLUE}Key Permissions:${NC}"
    ls -la "${KEYS_DIR}"/sa.* | while read line; do echo "  $line"; done
}

function generate_jwks() {
    echo -e "${GREEN}Generating JWKS from public key...${NC}"
    
    if [ ! -f "${KEYS_DIR}/sa.pub" ]; then
        echo -e "${RED}Public key not found${NC}"
        return 1
    fi
    
    # Extract modulus and exponent
    MODULUS=$(openssl rsa -pubin -in "${KEYS_DIR}/sa.pub" -modulus -noout | cut -d= -f2)
    EXPONENT=$(openssl rsa -pubin -in "${KEYS_DIR}/sa.pub" -text -noout | grep Exponent | awk '{print $2}')
    
    # Convert to base64url
    MOD_B64=$(echo -n "$MODULUS" | xxd -r -p | base64 | tr '+/' '-_' | tr -d '=')
    EXP_B64=$(printf "%x" $EXPONENT | xxd -r -p | base64 | tr '+/' '-_' | tr -d '=')
    
    # Generate key ID (kid) from key hash
    KID=$(openssl rsa -pubin -in "${KEYS_DIR}/sa.pub" -outform DER 2>/dev/null | openssl dgst -sha256 | awk '{print $2}' | head -c 8)
    
    # Create JWKS
    JWKS_FILE="${KEYS_DIR}/jwks.json"
    cat > "${JWKS_FILE}" <<EOF
{
  "keys": [
    {
      "kty": "RSA",
      "alg": "RS256",
      "use": "sig",
      "kid": "${KID}",
      "n": "${MOD_B64}",
      "e": "${EXP_B64}"
    }
  ]
}
EOF
    
    echo -e "${GREEN}✓ JWKS generated: ${JWKS_FILE}${NC}"
    echo ""
    echo "JWKS content:"
    cat "${JWKS_FILE}" | jq '.' 2>/dev/null || cat "${JWKS_FILE}"
}

# Main script logic
case "${1:-help}" in
    generate)
        generate_keys
        ;;
    validate)
        validate_keys
        ;;
    backup)
        backup_keys
        ;;
    restore)
        restore_keys
        ;;
    info)
        show_info
        ;;
    jwks)
        generate_jwks
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac