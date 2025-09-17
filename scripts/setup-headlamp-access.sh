#!/usr/bin/env bash

set -euo pipefail

# Script to set up optimized kubeconfig for Headlamp Windows Desktop
# Uses vcluster CLI's native features for efficient connection management
# Generates a consolidated kubeconfig accessible from Windows

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VCLUSTER_ENVS=("dev" "staging")
detect_host_context() {
  if [ -n "${HOST_CONTEXT:-}" ]; then
    echo "$HOST_CONTEXT"
    return
  fi
  local ctx
  ctx=$(kubectl config get-contexts -o name 2>/dev/null | grep '^kind-' | tail -1)
  if [ -z "$ctx" ]; then
    ctx=$(kubectl config current-context 2>/dev/null || echo "")
  fi
  if [ -z "$ctx" ]; then
    ctx="kind-localdev"
  fi
  echo "$ctx"
}

HOST_CONTEXT=$(detect_host_context)
WINDOWS_HOME="/mnt/c/Users/VinodPittampalli"  # Windows username is different from WSL username
OUTPUT_DIR="${HOME}/.kube/headlamp"
OUTPUT_FILE="${OUTPUT_DIR}/config"
WINDOWS_OUTPUT="${WINDOWS_HOME}/.kube/headlamp-config"
PORT_START=${PORT_START:-8443}

# Ensure required tools
if ! command -v vcluster >/dev/null 2>&1; then
  echo -e "${RED}Error: vcluster CLI is required${NC}" >&2
  echo "Install with: curl -L -o vcluster 'https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64' && chmod +x vcluster && sudo mv vcluster /usr/local/bin" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "${RED}Error: kubectl is required${NC}" >&2
  exit 1
fi

echo -e "${GREEN}=== Headlamp Access Setup ===${NC}"
echo -e "${BLUE}Generating optimized kubeconfig for Windows Headlamp${NC}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Initialize new kubeconfig
cat > "${OUTPUT_FILE}" <<EOF
apiVersion: v1
kind: Config
preferences: {}
clusters: []
contexts: []
users: []
current-context: ""
EOF

echo -e "${GREEN}Step 1: Adding host cluster context${NC}"

# Export host cluster context
if kubectl config view --context="${HOST_CONTEXT}" --minify --flatten > /tmp/host-config.yaml 2>/dev/null; then
  # Merge host config
  KUBECONFIG="${OUTPUT_FILE}:/tmp/host-config.yaml" kubectl config view --flatten > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  echo -e "  ${GREEN}✓${NC} Added host cluster: ${HOST_CONTEXT}"
else
  echo -e "  ${YELLOW}⚠${NC} Could not find host context: ${HOST_CONTEXT}"
fi

echo ""
echo -e "${GREEN}Step 2: Adding vcluster contexts${NC}"

CURRENT_PORT=${PORT_START}
VCLUSTER_CONFIGS=()

for ENV in "${VCLUSTER_ENVS[@]}"; do
  NAMESPACE="${ENV}-vcluster"
  NAME="vcluster-${ENV}-helm"
  CONTEXT="${ENV}-vcluster"
  
  echo -e "${BLUE}Processing ${ENV} vcluster...${NC}"
  
  # Check if vcluster exists
  if ! kubectl get pod "${NAME}-0" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo -e "  ${YELLOW}⚠${NC} VCluster ${NAME} not found, skipping"
    continue
  fi
  
  # Check pod status
  POD_STATUS=$(kubectl get pod "${NAME}-0" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)
  if [[ "${POD_STATUS}" != "Running" ]]; then
    echo -e "  ${YELLOW}⚠${NC} VCluster ${NAME} not running (${POD_STATUS}), skipping"
    continue
  fi
  
  # Generate vcluster kubeconfig using native CLI features
  TEMP_CONFIG=$(mktemp)
  
  echo -e "  Generating kubeconfig for ${ENV} (port ${CURRENT_PORT})..."
  
  # Use vcluster CLI with optimized flags
  if vcluster connect "${NAME}" \
    --namespace "${NAMESPACE}" \
    --server "https://localhost:${CURRENT_PORT}" \
    --kube-config-context-name "${CONTEXT}" \
    --insecure \
    --update-current=false \
    --print > "${TEMP_CONFIG}" 2>/dev/null; then
    
    # Merge into consolidated config
    KUBECONFIG="${OUTPUT_FILE}:${TEMP_CONFIG}" kubectl config view --flatten > "${OUTPUT_FILE}.tmp"
    mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    
    echo -e "  ${GREEN}✓${NC} Added ${CONTEXT} (localhost:${CURRENT_PORT})"
    
    # Store config info for later
    VCLUSTER_CONFIGS+=("${ENV}:${CURRENT_PORT}")
    
    CURRENT_PORT=$((CURRENT_PORT + 1))
  else
    echo -e "  ${RED}✗${NC} Failed to generate config for ${ENV}"
  fi
  
  rm -f "${TEMP_CONFIG}"
done

echo ""
echo -e "${GREEN}Step 3: Optimizing for Windows access${NC}"

# Ensure Windows-compatible paths
if [[ -d "${WINDOWS_HOME}" ]]; then
  # Create Windows .kube directory if it doesn't exist
  WINDOWS_KUBE_DIR="${WINDOWS_HOME}/.kube"
  if [[ ! -d "${WINDOWS_KUBE_DIR}" ]]; then
    echo -e "  Creating Windows .kube directory..."
    mkdir -p "${WINDOWS_KUBE_DIR}"
  fi
  
  # Copy config to Windows-accessible location
  cp "${OUTPUT_FILE}" "${WINDOWS_OUTPUT}"
  echo -e "  ${GREEN}✓${NC} Config copied to Windows: ${WINDOWS_OUTPUT}"
  
  # Convert to Windows paths in the config
  # Note: Headlamp should handle this automatically, but we'll keep Unix paths
  # since it's running in WSL2 context
else
  echo -e "  ${YELLOW}⚠${NC} Windows home directory not found at ${WINDOWS_HOME}"
  echo -e "  ${BLUE}ℹ${NC} Config saved to: ${OUTPUT_FILE}"
fi

echo ""
echo -e "${GREEN}Step 4: Creating port-forward management script${NC}"

# Create port-forward script
cat > "${OUTPUT_DIR}/start-port-forwards.sh" <<'SCRIPT_EOF'
#!/usr/bin/env bash

# Port-forward management for Headlamp access
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration - will be replaced with actual values
VCLUSTER_CONFIGS=(
SCRIPT_EOF

# Add actual vcluster configs
for CONFIG in "${VCLUSTER_CONFIGS[@]}"; do
  echo "  \"${CONFIG}\"" >> "${OUTPUT_DIR}/start-port-forwards.sh"
done

cat >> "${OUTPUT_DIR}/start-port-forwards.sh" <<'SCRIPT_EOF'
)

echo -e "${GREEN}=== Starting Port Forwards for Headlamp ===${NC}"
echo ""

# Function to check if port is in use
port_in_use() {
  lsof -i :"$1" >/dev/null 2>&1
}

# Function to start port-forward
start_port_forward() {
  local env=$1
  local port=$2
  local namespace="${env}-vcluster"
  local service="vcluster-${env}-helm"
  
  echo -e "${BLUE}Starting port-forward for ${env} on port ${port}...${NC}"
  
  # Check if port is already in use
  if port_in_use "${port}"; then
    echo -e "  ${YELLOW}⚠${NC} Port ${port} already in use"
    
    # Check if it's our port-forward
    if ps aux | grep -q "[k]ubectl port-forward.*${service}.*${port}"; then
      echo -e "  ${GREEN}✓${NC} Port-forward already running for ${env}"
    else
      echo -e "  ${RED}✗${NC} Port ${port} used by another process"
      echo "    Kill existing process or use a different port"
    fi
    return 1
  fi
  
  # Start port-forward in background
  kubectl port-forward -n "${namespace}" "svc/${service}" "${port}:443" >/dev/null 2>&1 &
  local pid=$!
  
  # Wait a moment to check if it started successfully
  sleep 2
  
  if kill -0 $pid 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Started port-forward for ${env} (PID: $pid)"
    echo "    Access via: https://localhost:${port}"
  else
    echo -e "  ${RED}✗${NC} Failed to start port-forward for ${env}"
    return 1
  fi
}

# Process each vcluster
for CONFIG in "${VCLUSTER_CONFIGS[@]}"; do
  IFS=':' read -r env port <<< "${CONFIG}"
  start_port_forward "${env}" "${port}" || true
  echo ""
done

echo -e "${GREEN}=== Port Forwards Active ===${NC}"
echo ""
echo "Port-forward processes:"
ps aux | grep "[k]ubectl port-forward" | grep vcluster || echo "  None found"

echo ""
echo -e "${BLUE}To stop all port-forwards:${NC}"
echo "  pkill -f 'kubectl port-forward.*vcluster'"

echo ""
echo -e "${GREEN}Headlamp can now connect to all clusters!${NC}"
echo "  Host cluster: directly accessible"

for CONFIG in "${VCLUSTER_CONFIGS[@]}"; do
  IFS=':' read -r env port <<< "${CONFIG}"
  echo "  ${env}-vcluster: via localhost:${port}"
done
SCRIPT_EOF

chmod +x "${OUTPUT_DIR}/start-port-forwards.sh"
echo -e "  ${GREEN}✓${NC} Created port-forward script: ${OUTPUT_DIR}/start-port-forwards.sh"

echo ""
echo -e "${GREEN}Step 5: Creating Windows PowerShell helper${NC}"

# Create PowerShell script for Windows side
cat > "${OUTPUT_DIR}/headlamp-setup.ps1" <<'PS_EOF'
# PowerShell script to configure Headlamp for WSL2 Kubernetes clusters
# Run this in Windows PowerShell as Administrator if needed

$ErrorActionPreference = "Stop"

Write-Host "=== Headlamp Configuration for WSL2 Clusters ===" -ForegroundColor Green
Write-Host ""

# Configuration
$kubeconfigPath = "$env:USERPROFILE\.kube\headlamp-config"
$headlampPath = "$env:LOCALAPPDATA\Headlamp"

# Check if kubeconfig exists
if (!(Test-Path $kubeconfigPath)) {
    Write-Host "Error: Kubeconfig not found at $kubeconfigPath" -ForegroundColor Red
    Write-Host "Please run setup-headlamp-access.sh in WSL2 first" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found kubeconfig at: $kubeconfigPath" -ForegroundColor Green

# Set KUBECONFIG environment variable for current session
$env:KUBECONFIG = $kubeconfigPath
Write-Host "Set KUBECONFIG for current session" -ForegroundColor Green

# Set KUBECONFIG permanently for user
[System.Environment]::SetEnvironmentVariable("KUBECONFIG", $kubeconfigPath, [System.EnvironmentVariableTarget]::User)
Write-Host "Set KUBECONFIG permanently for user" -ForegroundColor Green

# Check if Headlamp is installed
$headlampExe = Get-Command headlamp -ErrorAction SilentlyContinue
if ($headlampExe) {
    Write-Host "Headlamp found at: $($headlampExe.Path)" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Starting Headlamp with WSL2 kubeconfig..." -ForegroundColor Blue
    Write-Host "Note: Ensure port-forwards are running in WSL2" -ForegroundColor Yellow
    
    # Start Headlamp
    Start-Process "headlamp"
} else {
    Write-Host "Headlamp not found. Please install from: https://headlamp.dev/" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "After installation, you can:" -ForegroundColor Blue
    Write-Host "  1. Start Headlamp from Start Menu"
    Write-Host "  2. Or run 'headlamp' from PowerShell"
}

Write-Host ""
Write-Host "=== Configuration Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Remember to:" -ForegroundColor Blue
Write-Host "  1. Run port-forwards in WSL2: ~/.kube/headlamp/start-port-forwards.sh"
Write-Host "  2. Keep port-forwards running while using Headlamp"
Write-Host "  3. Refresh Headlamp if connections fail"
PS_EOF

if [[ -d "${WINDOWS_HOME}" ]]; then
  cp "${OUTPUT_DIR}/headlamp-setup.ps1" "${WINDOWS_HOME}/.kube/headlamp-setup.ps1"
  echo -e "  ${GREEN}✓${NC} PowerShell script copied to Windows: ${WINDOWS_HOME}/.kube/headlamp-setup.ps1"
else
  echo -e "  ${BLUE}ℹ${NC} PowerShell script saved to: ${OUTPUT_DIR}/headlamp-setup.ps1"
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${GREEN}Quick Start Guide:${NC}"
echo ""
echo "1. ${BLUE}Start port-forwards (WSL2):${NC}"
echo "   ${OUTPUT_DIR}/start-port-forwards.sh"
echo ""
echo "2. ${BLUE}Configure Headlamp (Windows):${NC}"
if [[ -d "${WINDOWS_HOME}" ]]; then
  echo "   Open PowerShell and run:"
  echo "   .\\$(basename "${WINDOWS_HOME}")\\.kube\\headlamp-setup.ps1"
else
  echo "   Copy ${OUTPUT_DIR}/headlamp-setup.ps1 to Windows and run in PowerShell"
fi
echo ""
echo "3. ${BLUE}Access clusters in Headlamp:${NC}"
echo "   - Host cluster: ${HOST_CONTEXT}"
for CONFIG in "${VCLUSTER_CONFIGS[@]}"; do
  IFS=':' read -r env port <<< "${CONFIG}"
  echo "   - ${env}-vcluster: via localhost:${port}"
done
echo ""
echo -e "${GREEN}Files created:${NC}"
echo "  - Kubeconfig: ${OUTPUT_FILE}"
if [[ -f "${WINDOWS_OUTPUT}" ]]; then
  echo "  - Windows config: ${WINDOWS_OUTPUT}"
fi
echo "  - Port-forward script: ${OUTPUT_DIR}/start-port-forwards.sh"
echo "  - PowerShell helper: ${OUTPUT_DIR}/headlamp-setup.ps1"
echo ""
echo -e "${YELLOW}Tips:${NC}"
echo "  • Port-forwards must be running for vcluster access"
echo "  • Use tmux/screen to keep port-forwards alive"
echo "  • If connection fails, restart port-forwards"
echo "  • Headlamp auto-refreshes every 10 seconds"
