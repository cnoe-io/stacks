#!/bin/bash
# Complete CAIPE + i3 VNC Setup Script
# Combines i3 desktop environment with IDPBuilder platform setup
# Run with: curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/caipe/setup-ubuntu-prerequisites.sh | bash
# Or with profile: curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/caipe/setup-ubuntu-prerequisites.sh | bash -s -- --profile caipe-complete-p2p

set -e

# Default values
CAIPE_PROFILE="caipe-complete-p2p"
SHOW_HELP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            CAIPE_PROFILE="$2"
            shift 2
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Show help if requested
if [[ "$SHOW_HELP" == "true" ]]; then
    echo "CAIPE + i3 VNC Setup Script"
    echo ""
    echo "Usage:"
    echo "  curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/caipe/setup-ubuntu-prerequisites.sh | bash"
    echo "  curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/caipe/setup-ubuntu-prerequisites.sh | bash -s -- --profile <profile>"
    echo ""
    echo "Options:"
    echo "  --profile <name>    CAIPE profile to use (default: caipe-complete-p2p)"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Available CAIPE Profiles:"
    echo "  caipe-complete-p2p  Complete CAIPE platform with P2P networking"
    echo "  caipe-basic-p2     Basic CAIPE platform with P2P networking"
    echo "  caipe-minimal      Minimal CAIPE setup"
    echo ""
    echo "Examples:"
    echo "  # Use default profile (caipe-complete-p2p)"
    echo "  curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/caipe/setup-ubuntu-prerequisites.sh | bash"
    echo ""
    echo "  # Use specific profile"
    echo "  curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/caipe/setup-ubuntu-prerequisites.sh | bash -s -- --profile caipe-basic-p2"
    exit 0
fi

echo "🚀 Setting up Complete CAIPE + i3 VNC environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to handle package installation with error recovery
install_package() {
    local package_name="$1"
    local description="${2:-$package_name}"

    # Check if package is already installed
    if dpkg -l | grep -q "^ii.*$package_name "; then
        print_success "$description is already installed"
        return 0
    fi

    print_status "Installing $description..."

    # First attempt
    if sudo apt install -y "$package_name"; then
        print_success "$description installed successfully"
        return 0
    fi

    # If first attempt fails, try to fix dependencies
    print_warning "Failed to install $description, attempting to fix dependencies..."
    sudo apt --fix-broken install -y || true
    sudo apt autoremove -y || true
    sudo apt update || true

    # Second attempt
    if sudo apt install -y "$package_name"; then
        print_success "$description installed successfully on second attempt"
        return 0
    fi

    # If still failing, try to remove conflicting packages and retry
    print_warning "Still failing, attempting to remove conflicting packages..."
    sudo apt remove -y amazon-q 2>/dev/null || true
    sudo apt autoremove -y || true
    sudo apt --fix-broken install -y || true

    # Third attempt
    if sudo apt install -y "$package_name"; then
        print_success "$description installed successfully after cleanup"
        return 0
    fi

    print_error "Failed to install $description after multiple attempts"
    return 1
}

# Function to handle command execution with error recovery
run_command() {
    local description="$1"
    local command="$2"

    print_status "$description..."
    if eval "$command"; then
        print_success "$description completed successfully"
    else
        print_warning "$description failed, continuing..."
        return 1
    fi
}

# Function to clean up duplicate repositories
cleanup_duplicate_repositories() {
    print_status "Cleaning up duplicate repositories..."

    # Remove duplicate HashiCorp repositories
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_apt_releases_hashicorp_com-*.list
    sudo rm -f /etc/apt/sources.list.d/hashicorp.list

    # Remove duplicate GitHub CLI repositories
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_cli_github_com_packages-*.list
    sudo rm -f /etc/apt/sources.list.d/github-cli.list

    # Remove duplicate Docker repositories
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_download_docker_com_linux_ubuntu-*.list
    sudo rm -f /etc/apt/sources.list.d/docker.list

    print_success "Repository cleanup completed"
}

# Function to aggressively clean up conflicting packages
cleanup_conflicting_packages() {
    print_status "Cleaning up conflicting packages..."

    # Check if amazon-q is causing issues
    if dpkg -l | grep -q amazon-q; then
        print_status "Found amazon-q package, attempting removal..."

        # First, try to fix broken dependencies
        print_status "Fixing broken dependencies..."
        sudo apt --fix-broken install -y || true

        # Try normal removal first
        print_status "Attempting normal removal of Amazon packages..."
        print_status "Removing only amazon-q package (other Amazon packages are snaps)..."
        sudo apt remove --purge -y amazon-q || true

        # Force remove if normal removal failed
        print_status "Force removing Amazon packages..."
        sudo dpkg --remove --force-remove-reinstreq amazon-q 2>/dev/null || true

        # Alternative: Install the missing dependency to resolve the conflict
        print_status "Installing missing WebKit dependency to resolve conflict..."
        sudo apt install -y libwebkit2gtk-4.1-0 || true

        # Clean up any remaining broken dependencies
        print_status "Final cleanup of broken dependencies..."
        sudo apt --fix-broken install -y || true
        sudo apt autoremove -y || true
        sudo apt autoclean || true

        # Update package lists
        sudo apt update || true

        # Verify the fix worked
        if sudo apt install -y curl >/dev/null 2>&1; then
            print_success "Package cleanup completed successfully"
        else
            print_warning "Package cleanup completed with warnings - some issues may persist"
        fi
    else
        print_status "No conflicting Amazon packages found, performing standard cleanup..."
        sudo apt --fix-broken install -y || true
        sudo apt autoremove -y || true
        sudo apt update || true
        print_success "Standard cleanup completed"
    fi
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
else
    print_error "Unsupported OS: $OSTYPE"
    exit 1
fi

print_status "Detected OS: $OS"

# =============================================================================
# PROFILE VALIDATION
# =============================================================================

# Validate CAIPE profile
validate_profile() {
    local profile="$1"
    case "$profile" in
        caipe-complete-p2p|caipe-basic-p2|caipe-minimal)
            return 0
            ;;
        *)
            print_error "Invalid CAIPE profile: $profile"
            echo ""
            echo "Available profiles:"
            echo "  caipe-complete-p2p  Complete CAIPE platform with P2P networking"
            echo "  caipe-basic-p2     Basic CAIPE platform with P2P networking"
            echo "  caipe-minimal      Minimal CAIPE setup"
            echo ""
            echo "Use --help for more information"
            exit 1
            ;;
    esac
}

# Validate the selected profile
validate_profile "$CAIPE_PROFILE"
print_success "Using CAIPE profile: $CAIPE_PROFILE"

# =============================================================================
# PRE-FLIGHT: FIX ANY EXISTING DEPENDENCY ISSUES
# =============================================================================

if [[ "$OS" == "linux" ]]; then
    print_status "Performing pre-flight dependency check..."

    # Clean up duplicate repositories first
    cleanup_duplicate_repositories

    # Force remove any remaining duplicate repository files
    print_status "Removing any remaining duplicate repository files..."
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_apt_releases_hashicorp_com-*.list
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_cli_github_com_packages-*.list
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_download_docker_com_linux_ubuntu-*.list

    # Check for broken dependencies
    if ! sudo apt install -y curl >/dev/null 2>&1; then
        print_warning "Detected broken dependencies, attempting to fix..."
        cleanup_conflicting_packages
    else
        print_success "No dependency issues detected"
    fi
fi

# =============================================================================
# PART 1: SYSTEM PREREQUISITES
# =============================================================================

print_status "Installing system prerequisites..."

if [[ "$OS" == "linux" ]]; then
    # Aggressively clean up conflicting packages first
    cleanup_conflicting_packages

    # Install basic tools
    install_package "vim" "vim"
    install_package "jq" "jq"
    install_package "software-properties-common" "software-properties-common"
    install_package "curl" "curl"
    install_package "wget" "wget"

    # Install Docker
    print_status "Installing Docker..."
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    install_package "docker-ce" "Docker CE"
    install_package "docker-ce-cli" "Docker CLI"
    install_package "containerd.io" "containerd"
    install_package "docker-buildx-plugin" "Docker Buildx"
    install_package "docker-compose-plugin" "Docker Compose"

    # Add user to docker group
    sudo groupadd docker 2>/dev/null || true
    sudo usermod -aG docker $USER

    # Install kubectl
    print_status "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    # Install Vault
    print_status "Installing Vault..."
    # Clean up any existing HashiCorp repositories to avoid duplicates
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_apt_releases_hashicorp_com-*.list
    sudo rm -f /etc/apt/sources.list.d/hashicorp.list

    # Use modern keyring method instead of deprecated apt-key
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    install_package "vault" "HashiCorp Vault"

    # Install GitHub CLI
    print_status "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    install_package "gh" "GitHub CLI"

    # Install K9s
    print_status "Installing K9s..."
    run_command "Downloading K9s" "wget https://github.com/derailed/k9s/releases/download/v0.50.12/k9s_linux_amd64.deb"
    run_command "Installing K9s" "sudo dpkg -i k9s_linux_amd64.deb || sudo apt --fix-broken install -y"
    rm -f k9s_linux_amd64.deb

elif [[ "$OS" == "mac" ]]; then
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        print_status "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Install tools via Homebrew
    brew install docker kind kubectl vault gh k9s
fi

# Install IDPBuilder
print_status "Installing IDPBuilder..."
if [[ "$OS" == "mac" ]]; then
    brew install cnoe-io/tap/idpbuilder
else
    arch=$(if [[ "$(uname -m)" == "x86_64" ]]; then echo "amd64"; else uname -m; fi)
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    idpbuilder_latest_tag=$(curl --silent "https://api.github.com/repos/cnoe-io/idpbuilder/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -LO https://github.com/cnoe-io/idpbuilder/releases/download/$idpbuilder_latest_tag/idpbuilder-$os-$arch.tar.gz
    tar xvzf idpbuilder-$os-$arch.tar.gz
    chmod +x idpbuilder
    sudo mv idpbuilder /usr/local/bin
    rm idpbuilder-linux-amd64.tar.gz LICENSE README.md 2>/dev/null || true
fi

# Install Kind
print_status "Installing Kind..."
if [[ "$OS" == "mac" ]]; then
    brew install kind
else
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

print_success "System prerequisites installed!"

# =============================================================================
# PART 2: i3 DESKTOP ENVIRONMENT SETUP
# =============================================================================

if [[ "$OS" == "linux" ]]; then
    print_status "Setting up i3 desktop environment..."

    # Remove GNOME (if present)
    sudo apt remove --purge ubuntu-desktop gnome-shell gnome-session gdm3 -y 2>/dev/null || true
    sudo apt autoremove --purge -y

    # Install i3 and VNC packages
    # Install required dependencies for webkit first
    install_package "libwebkit2gtk-4.1-0" "WebKit dependencies"

    install_package "i3" "i3 window manager"
    install_package "i3status" "i3 status bar"
    install_package "i3lock" "i3 screen locker"
    install_package "dmenu" "dmenu"
    install_package "rofi" "rofi launcher"
    install_package "xorg" "X.Org server"
    install_package "lightdm" "LightDM display manager"
    install_package "xterm" "xterm terminal"
    install_package "terminator" "Terminator terminal"
    install_package "xclip" "xclip clipboard utility"
    install_package "parcellite" "Parcellite clipboard manager"
    install_package "firefox" "Firefox browser"
    install_package "tigervnc-standalone-server" "TigerVNC server"

    # Create i3 config
    print_status "Creating i3 configuration..."
    mkdir -p ~/.config/i3
    cat > ~/.config/i3/config << 'EOF'
# i3 config - Mac compatible (Alt key)
set $mod Mod1
font pango:monospace 8
floating_modifier $mod

# Terminal shortcuts
bindsym $mod+Return exec terminator
bindsym $mod+t exec terminator

# Application shortcuts
bindsym $mod+Shift+q kill
bindsym $mod+d exec rofi -show run
bindsym $mod+space exec rofi -show drun
bindsym $mod+f exec firefox

# Navigation
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# Move windows
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# Splits and layout
bindsym $mod+h split h
bindsym $mod+v split v
bindsym $mod+F11 fullscreen toggle
bindsym $mod+Shift+space floating toggle
bindsym $mod+Tab focus mode_toggle

# Workspaces
set $ws1 "1"
set $ws2 "2"
set $ws3 "3"
set $ws4 "4"
set $ws5 "5"

bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5

bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5

# System
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"

# Status bar
bar {
    status_command i3status
}
EOF

    # Create VNC startup script
    print_status "Setting up VNC..."
    mkdir -p ~/.vnc
    cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
export DISPLAY=:1
xhost +local: &
xsetroot -solid grey &
parcellite &
terminator -g 80x24+10+10 &
firefox &
exec i3
EOF
    chmod +x ~/.vnc/xstartup

    print_success "i3 desktop environment configured!"
fi

# =============================================================================
# PART 3: IDPBuilder CLUSTER CREATION
# =============================================================================

print_status "Creating IDPBuilder cluster with CAIPE profile: $CAIPE_PROFILE..."

# Create the cluster with the selected CAIPE profile
idpbuilder create \
  --use-path-routing \
  --package https://github.com/cnoe-io/stacks//ref-implementation \
  --package https://github.com/sriaradhyula/stacks//caipe/$CAIPE_PROFILE

print_success "IDPBuilder cluster created with profile: $CAIPE_PROFILE!"

# =============================================================================
# PART 4: VERIFICATION AND ACCESS INFORMATION
# =============================================================================

print_status "Verifying cluster setup..."

# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Final cleanup and verification
print_status "Performing final cleanup and verification..."

# Fix any remaining broken dependencies
sudo apt --fix-broken install -y || true

# Clean up package cache
sudo apt autoremove -y
sudo apt autoclean

# Verify critical tools are installed
print_status "Verifying installation..."
for tool in docker kubectl vault gh k9s idpbuilder kind; do
    if command -v "$tool" &> /dev/null; then
        print_success "$tool is installed"
    else
        print_warning "$tool is not installed or not in PATH"
    fi
done

print_success "Setup complete! 🎉"
echo ""
echo "============================================================================="
echo "🚀 CAIPE + i3 VNC Environment Ready!"
echo "============================================================================="
echo ""

if [[ "$OS" == "linux" ]]; then
    echo "🖥️  VNC Desktop Access:"
    echo "   Start VNC: vncserver :1 -geometry 2560x1400 -depth 24 -localhost yes"
    echo "   SSH Tunnel: ssh -i ~/.ssh/caipe-complete-p2p.pem -L 5903:localhost:5901 ubuntu@3.142.69.179 -f -N"
    echo "   VNC Client: Connect to localhost:5903"
    echo ""
    echo "⌨️  i3 Keyboard Shortcuts (Alt = Mod key):"
    echo "   Alt+Return - Terminal"
    echo "   Alt+d - App launcher"
    echo "   Alt+Space - App menu"
    echo "   Alt+f - Firefox"
    echo "   Alt+1,2,3,4,5 - Workspaces"
    echo ""
fi

echo "🌐 Platform Access URLs:"
echo "   ArgoCD: https://cnoe.localtest.me:8443/argocd/"
echo "   Backstage: https://cnoe.localtest.me:8443/"
echo "   Vault: https://vault.cnoe.localtest.me:8443/"
echo "   Keycloak: https://cnoe.localtest.me:8443/keycloak/admin/master/console/"
echo "   Gitea: https://cnoe.localtest.me:8443/gitea/"
echo ""

echo "🔐 Getting Credentials:"
echo "   ArgoCD Admin Password:"
idpbuilder get secrets -p argocd
echo ""
echo "   Backstage User Password:"
idpbuilder get secrets | grep USER_PASSWORD | sed 's/.*USER_PASSWORD=\([^,]*\).*/\1/'
echo ""

echo "🔧 Vault Configuration:"
echo "   Root Token:"
kubectl get secret vault-root-token -n vault -o jsonpath="{.data}" | \
  jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'
echo ""

echo "📚 Next Steps:"
echo "   1. Access Vault UI and configure LLM provider secrets"
echo "   2. Login to Backstage and test the AI agent"
echo "   3. Explore the platform components via ArgoCD"
echo ""

echo "🧹 Cleanup (when done):"
echo "   kind delete cluster --name localdev"
echo ""

print_success "Happy platform engineering! 🚀"

# =============================================================================
# PART 5: VNC SETUP (FINAL STEP)
# =============================================================================

if [[ "$OS" == "linux" ]]; then
    print_status "Setting up VNC access..."

    # # Set VNC password
    # print_status "Setting VNC password (you'll be prompted)..."
    # vncpasswd

    # Start VNC server
    print_status "Starting VNC server..."
    vncserver :1 -geometry 2560x1400 -depth 24 -localhost yes

    print_success "VNC server started successfully!"
    echo ""
    echo "🖥️  VNC Desktop Access:"
    echo "   Start VNC: vncserver :1 -geometry 2560x1400 -depth 24 -localhost yes"
    echo "   SSH Tunnel: ssh -i ~/.ssh/caipe-complete-p2p.pem -L 5903:localhost:5901 ubuntu@3.142.69.179 -f -N"
    echo "   VNC Client: Connect to localhost:5903"
    echo ""

    echo "======================================================================"
    echo "        🖥️  VNC ACCESS INSTRUCTIONS & SECURITY RECOMMENDATIONS        "
    echo "======================================================================"
    echo ""
    echo "🔑 NOTE: You must set a VNC password before connecting with TigerVNC, VNC Viewer, or using screen sharing clients."
    echo "   To set your VNC password, run:"
    echo "      vncpasswd"
    echo ""
    echo "💻 To connect from your local machine:"
    echo "   - On Mac:"
    echo "       1. Open Finder, press Cmd+K, and enter: vnc://localhost:5903"
    echo "       2. Or use a VNC client like TigerVNC or RealVNC Viewer and connect to localhost:5903"
    echo "   - On Windows:"
    echo "       1. Download and install TigerVNC or RealVNC Viewer"
    echo "       2. Connect to: localhost:5903"
    echo ""
    echo "🔒 For better security and compression, tunnel VNC via SSH:"
    echo "   Example command:"
    echo "      ssh -i ~/.ssh/caipe-complete-p2p.pem -L 5903:localhost:5901 ubuntu@3.142.69.179 -f -N"
    echo "   This forwards your local port 5903 to the remote VNC server's port 5901."
    echo "   Then connect your VNC client to localhost:5903."
    echo ""
    echo "   (Make sure to set up the SSH tunnel as shown above before connecting!)"
    echo "======================================================================"
fi
