#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CERT_SECRET_NAME="${CERT_SECRET_NAME:-idpbuilder-cert}"
CERT_NAMESPACE="${CERT_NAMESPACE:-ingress-nginx}"
REGISTRY_HOST="${REGISTRY_HOST:-gitea.cnoe.localtest.me:8443}"
STACKS_DIR="${STACKS_DIR:-$HOME/stacks}"
CERT_CACHE_DIR="$STACKS_DIR/certificates"
SYSTEM_CERT_DIR="$STACKS_DIR/certs"
BROWSER_SCRIPT="$STACKS_DIR/scripts/setup-browser-certs.sh"
TARGET_USER="${TARGET_USER:-$(id -un)}"
MODE="user"
FORCE_UPDATE=false

usage() {
    cat <<'HELP'
Usage: sync-cluster-certificates.sh [--system] [--force]

Modes:
  (default)   Extract certificate from the running cluster, refresh overrides,
              and trigger system installation.
  --system    Only install certificates into system trust stores using the copy
              stored under ~/stacks/certs. Intended for the systemd service.

Options:
  --force     Re-extract and overwrite even if the saved fingerprint matches the
              cluster.
  -h, --help  Show this help message.
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)
            MODE="system"
            shift
            ;;
        --force)
            FORCE_UPDATE=true
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

log() {
    echo -e "${GREEN}➜${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error_exit() {
    echo -e "${RED}✖${NC} $1" >&2
    exit 1
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

ensure_binary() {
    if ! command -v "$1" >/dev/null 2>&1; then
        error_exit "Required command '$1' not found"
    fi
}

install_system_certificate() {
    local ca_path="$SYSTEM_CERT_DIR/idpbuilder-ca.crt"
    if [ ! -f "$ca_path" ]; then
        error_exit "CA certificate not found at $ca_path. Run script without --system first."
    fi

    log "Installing CA into /usr/local/share/ca-certificates"
    run_as_root install -Dm0644 "$ca_path" /usr/local/share/ca-certificates/idpbuilder-local.crt

    local update_ca
    if update_ca=$(command -v update-ca-certificates 2>/dev/null); then
        run_as_root "$update_ca"
    else
        local trust_bin
        trust_bin=$(command -v trust 2>/dev/null || true)
        if [ -z "$trust_bin" ] && [ -x /run/current-system/sw/bin/trust ]; then
            trust_bin=/run/current-system/sw/bin/trust
        fi
        if [ -n "$trust_bin" ]; then
            run_as_root "$trust_bin" anchor --store /usr/local/share/ca-certificates/idpbuilder-local.crt
        else
            warn "No system CA update helper found; relying on certificate copy only"
        fi
    fi

    log "Syncing Docker trust store"
    run_as_root install -d "/etc/docker/certs.d/$REGISTRY_HOST"
    run_as_root install -m0644 "$ca_path" "/etc/docker/certs.d/$REGISTRY_HOST/ca.crt"

if [ -n "$TARGET_USER" ]; then
    while IFS=: read -r user_name _ _ _ _ user_home _; do
        [ "$user_name" = "$TARGET_USER" ] || continue
        user_group=$(id -gn "$TARGET_USER")
        run_as_root install -d -o "$TARGET_USER" -g "$user_group" "$user_home/.docker/certs.d/$REGISTRY_HOST"
        run_as_root install -m0644 -o "$TARGET_USER" -g "$user_group" "$ca_path" "$user_home/.docker/certs.d/$REGISTRY_HOST/ca.crt"
        run_as_root install -d -o "$TARGET_USER" -g "$user_group" "$user_home/.local/share/cluster-certs"
        run_as_root install -m0644 -o "$TARGET_USER" -g "$user_group" "$ca_path" "$user_home/.local/share/cluster-certs/idpbuilder-ca.crt"
        if [ -f "$SYSTEM_CERT_DIR/ca-bundle-with-idpbuilder.crt" ]; then
            run_as_root install -m0644 -o "$TARGET_USER" -g "$user_group" "$SYSTEM_CERT_DIR/ca-bundle-with-idpbuilder.crt" "$user_home/.local/share/cluster-certs/ca-bundle-with-idpbuilder.crt"
        fi
        break
    done < /etc/passwd
fi

    log "System trust stores updated"
}

if [ "$MODE" = "system" ]; then
    install_system_certificate
    exit 0
fi

ensure_binary kubectl
ensure_binary openssl

log "Waiting for secret ${CERT_SECRET_NAME} in namespace ${CERT_NAMESPACE}"
for attempt in {1..30}; do
    if kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" &>/dev/null; then
        break
    fi
    sleep 2
    if [ "$attempt" -eq 30 ]; then
        error_exit "Secret ${CERT_SECRET_NAME} not found in namespace ${CERT_NAMESPACE}"
    fi
done

mkdir -p "$CERT_CACHE_DIR" "$SYSTEM_CERT_DIR"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$tmpdir/tls.crt"
kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > "$tmpdir/tls.key"
ca_b64=$(kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
if [ -n "$ca_b64" ]; then
    echo "$ca_b64" | base64 -d > "$tmpdir/ca.crt"
else
    # Fallback: derive CA from the TLS certificate (self-signed)
    openssl x509 -in "$tmpdir/tls.crt" -out "$tmpdir/ca.crt"
fi

new_fingerprint=$(openssl x509 -in "$tmpdir/tls.crt" -noout -fingerprint | cut -d= -f2)
if [ -f "$CERT_CACHE_DIR/tls.crt" ]; then
    existing_fingerprint=$(openssl x509 -in "$CERT_CACHE_DIR/tls.crt" -noout -fingerprint | cut -d= -f2)
else
    existing_fingerprint=""
fi

if [ "$existing_fingerprint" = "$new_fingerprint" ] && ! $FORCE_UPDATE; then
    warn "Certificate fingerprint unchanged (${new_fingerprint}). Skipping extraction."
else
    log "Updating stored certificate (fingerprint ${new_fingerprint})"
    install -m0644 "$tmpdir/tls.crt" "$CERT_CACHE_DIR/tls.crt"
    install -m0600 "$tmpdir/tls.key" "$CERT_CACHE_DIR/tls.key"
    install -m0644 "$tmpdir/ca.crt" "$CERT_CACHE_DIR/ca.crt"

    install -m0644 "$tmpdir/ca.crt" "$SYSTEM_CERT_DIR/idpbuilder-ca.crt"
    install -m0644 "$tmpdir/tls.crt" "$SYSTEM_CERT_DIR/idpbuilder-tls.crt"

    if [ -f /etc/ssl/certs/ca-bundle.crt ]; then
        cat /etc/ssl/certs/ca-bundle.crt "$tmpdir/ca.crt" > "$SYSTEM_CERT_DIR/ca-bundle-with-idpbuilder.crt"
        cat /etc/ssl/certs/ca-bundle.crt "$tmpdir/ca.crt" > "$CERT_CACHE_DIR/ca-bundle-with-idpbuilder.crt"
    fi

    if [ "$(id -u)" -ne 0 ] && [ -f "$SYSTEM_CERT_DIR/ca-bundle-with-idpbuilder.crt" ]; then
        mkdir -p "$HOME/.local/share/cluster-certs"
        cp "$SYSTEM_CERT_DIR/ca-bundle-with-idpbuilder.crt" "$HOME/.local/share/cluster-certs/ca-bundle-with-idpbuilder.crt"
    fi
fi

if [ -x "$BROWSER_SCRIPT" ]; then
    log "Importing certificate into browser profiles (Firefox and Chromium)"
    "$BROWSER_SCRIPT" --cert-file "$SYSTEM_CERT_DIR/idpbuilder-ca.crt" --no-cluster-check
else
    warn "Browser import script not found at $BROWSER_SCRIPT"
fi

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        log "Triggering system trust installation"
        sudo STACKS_DIR="$STACKS_DIR" TARGET_USER="$TARGET_USER" REGISTRY_HOST="$REGISTRY_HOST" "$STACKS_DIR/scripts/sync-cluster-certificates.sh" --system
    else
        warn "sudo not found; system trust stores not updated automatically"
    fi
fi

log "Certificate sync complete"
