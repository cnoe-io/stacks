#!/bin/bash
# Complete CAIPE + i3 VNC Setup Script
# Combines i3 desktop environment with IDPBuilder platform setup
# Run with: bash setup-ubuntu-prerequisites.sh
#
# This script runs in non-interactive mode to avoid package configuration prompts.
# It preconfigures keyboard layout (US English), timezone (America/New_York), 
# locale (en_US.UTF-8), and display manager (lightdm) to prevent interactive dialogs during installation.

set -e

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

echo "🚀 Setting up CAIPE Ubuntu prerequisites..."

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

    # First attempt with non-interactive flags
    if DEBIAN_FRONTEND=noninteractive sudo apt install -y -q "$package_name"; then
        print_success "$description installed successfully"
        return 0
    fi

    # If first attempt fails, try to fix dependencies
    print_warning "Failed to install $description, attempting to fix dependencies..."
    DEBIAN_FRONTEND=noninteractive sudo apt --fix-broken install -y -q || true
    DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y -q || true
    sudo apt update -q || true

    # Second attempt with non-interactive flags
    if DEBIAN_FRONTEND=noninteractive sudo apt install -y -q "$package_name"; then
        print_success "$description installed successfully on second attempt"
        return 0
    fi

    # If still failing, try to remove conflicting packages and retry
    print_warning "Still failing, attempting to remove conflicting packages..."
    DEBIAN_FRONTEND=noninteractive sudo apt remove -y -q amazon-q 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y -q || true
    DEBIAN_FRONTEND=noninteractive sudo apt --fix-broken install -y -q || true

    # Third attempt with non-interactive flags
    if DEBIAN_FRONTEND=noninteractive sudo apt install -y -q "$package_name"; then
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
        DEBIAN_FRONTEND=noninteractive sudo apt --fix-broken install -y -q || true

        # Try normal removal first
        print_status "Attempting normal removal of Amazon packages..."
        print_status "Removing only amazon-q package (other Amazon packages are snaps)..."
        DEBIAN_FRONTEND=noninteractive sudo apt remove --purge -y -q amazon-q || true

        # Force remove if normal removal failed
        print_status "Force removing Amazon packages..."
        sudo dpkg --remove --force-remove-reinstreq amazon-q 2>/dev/null || true

        # Alternative: Install the missing dependency to resolve the conflict
        print_status "Installing missing WebKit dependency to resolve conflict..."
        DEBIAN_FRONTEND=noninteractive sudo apt install -y -q libwebkit2gtk-4.1-0 || true

        # Clean up any remaining broken dependencies
        print_status "Final cleanup of broken dependencies..."
        DEBIAN_FRONTEND=noninteractive sudo apt --fix-broken install -y -q || true
        DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y -q || true
        DEBIAN_FRONTEND=noninteractive sudo apt autoclean || true

        # Update package lists
        sudo apt update -q || true

        # Verify the fix worked
        if DEBIAN_FRONTEND=noninteractive sudo apt install -y -q curl >/dev/null 2>&1; then
            print_success "Package cleanup completed successfully"
        else
            print_warning "Package cleanup completed with warnings - some issues may persist"
        fi
    else
        print_status "No conflicting Amazon packages found, performing standard cleanup..."
        DEBIAN_FRONTEND=noninteractive sudo apt --fix-broken install -y -q || true
        DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y -q || true
        sudo apt update -q || true
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
# PRE-FLIGHT: FIX ANY EXISTING DEPENDENCY ISSUES
# =============================================================================

if [[ "$OS" == "linux" ]]; then
    print_status "Configuring non-interactive installation mode..."
    
    # Set non-interactive mode to prevent prompts during package installation
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    
    # Prevent automatic service restarts during package installation
    echo '$nrconf{restart} = "a";' | sudo tee /etc/needrestart/conf.d/50local.conf >/dev/null 2>&1 || true
    
    # Preconfigure keyboard to avoid interactive prompt
    print_status "Preconfiguring keyboard layout (US English)..."
    echo 'keyboard-configuration keyboard-configuration/layoutcode string us' | sudo debconf-set-selections
    echo 'keyboard-configuration keyboard-configuration/modelcode string pc105' | sudo debconf-set-selections
    echo 'keyboard-configuration keyboard-configuration/variant select USA' | sudo debconf-set-selections
    echo 'keyboard-configuration keyboard-configuration/layout select English (US)' | sudo debconf-set-selections
    echo 'keyboard-configuration keyboard-configuration/store_defaults_in_debconf_db boolean true' | sudo debconf-set-selections
    
    # Preconfigure other common interactive prompts
    echo 'tzdata tzdata/Areas select America' | sudo debconf-set-selections
    echo 'tzdata tzdata/Zones/America select New_York' | sudo debconf-set-selections
    echo 'locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8' | sudo debconf-set-selections
    echo 'locales locales/default_environment_locale select en_US.UTF-8' | sudo debconf-set-selections
    
    # Preconfigure display manager (lightdm for i3 setup)
    echo 'lightdm shared/default-x-display-manager select lightdm' | sudo debconf-set-selections
    echo 'gdm3 shared/default-x-display-manager select lightdm' | sudo debconf-set-selections
    
    # Preconfigure other common interactive packages
    echo 'wireshark-common wireshark-common/install-setuid boolean false' | sudo debconf-set-selections
    echo 'console-setup console-setup/charmap47 select UTF-8' | sudo debconf-set-selections
    echo 'console-setup console-setup/codeset47 select # Latin1 and Latin5 - western Europe and Turkic languages' | sudo debconf-set-selections
    echo 'console-setup console-setup/codesetcode string Lat15' | sudo debconf-set-selections
    echo 'console-setup console-setup/fontface47 select Fixed' | sudo debconf-set-selections
    echo 'console-setup console-setup/fontsize-text47 select 16' | sudo debconf-set-selections
    echo 'console-setup console-setup/fontsize-fb47 select 16' | sudo debconf-set-selections
    
    print_status "Performing pre-flight dependency check..."

    # Clean up duplicate repositories first
    cleanup_duplicate_repositories

    # Force remove any remaining duplicate repository files
    print_status "Removing any remaining duplicate repository files..."
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_apt_releases_hashicorp_com-*.list
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_cli_github_com_packages-*.list
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_download_docker_com_linux_ubuntu-*.list

    # Check for broken dependencies
    if ! DEBIAN_FRONTEND=noninteractive sudo apt install -y -q curl >/dev/null 2>&1; then
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
    install_package "git" "git"
    install_package "vim" "vim"
    install_package "jq" "jq"
    install_package "software-properties-common" "software-properties-common"
    install_package "curl" "curl"
    install_package "wget" "wget"

    # Install Docker
    print_status "Installing Docker..."
    DEBIAN_FRONTEND=noninteractive sudo apt install -y -q ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update -q
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
    sudo apt update -q
    install_package "vault" "HashiCorp Vault"

    # Install GitHub CLI
    print_status "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update -q
    install_package "gh" "GitHub CLI"

    # Install K9s
    print_status "Installing K9s..."
    run_command "Downloading K9s" "wget https://github.com/derailed/k9s/releases/download/v0.50.12/k9s_linux_amd64.deb"
    run_command "Installing K9s" "sudo dpkg -i k9s_linux_amd64.deb || DEBIAN_FRONTEND=noninteractive sudo apt --fix-broken install -y -q"
    rm -f k9s_linux_amd64.deb

elif [[ "$OS" == "mac" ]]; then
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        print_status "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Install tools via Homebrew
    brew install git docker kind kubectl vault gh k9s
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
# GIT AND GITHUB CLI SETUP
# =============================================================================

print_status "Setting up Git and GitHub CLI..."

# Check if git is configured
if ! git config --global user.name >/dev/null 2>&1 || ! git config --global user.email >/dev/null 2>&1; then
    print_warning "Git is not configured yet. You'll need to set up your git identity:"
    echo "   Run these commands to configure git:"
    echo "      git config --global user.name \"Your Name\""
    echo "      git config --global user.email \"your.email@example.com\""
    echo ""
else
    print_success "Git is already configured"
    echo "   Name: $(git config --global user.name)"
    echo "   Email: $(git config --global user.email)"
    echo ""
fi

# Check GitHub CLI authentication
if command -v gh &> /dev/null; then
    if gh auth status >/dev/null 2>&1; then
        print_success "GitHub CLI is already authenticated"
    else
        print_warning "GitHub CLI is installed but not authenticated"
        echo "   To authenticate with GitHub, run:"
        echo "      gh auth login"
        echo "   This will guide you through the authentication process"
        echo ""
    fi
fi

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

print_status "IDPBuilder cluster creation will be handled separately by the user"
print_status "To create a cluster, run: idpbuilder create --use-path-routing --package <your-package>"

# =============================================================================
# PART 4: VERIFICATION AND ACCESS INFORMATION
# =============================================================================

print_status "Verifying system setup..."

# Final cleanup and verification
print_status "Performing final cleanup and verification..."

# Fix any remaining broken dependencies
DEBIAN_FRONTEND=noninteractive sudo apt --fix-broken install -y -q || true

# Clean up package cache
DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y -q
DEBIAN_FRONTEND=noninteractive sudo apt autoclean

# Verify critical tools are installed
print_status "Verifying installation..."
for tool in git docker kubectl vault gh k9s idpbuilder kind; do
    if command -v "$tool" &> /dev/null; then
        print_success "$tool is installed"
    else
        print_warning "$tool is not installed or not in PATH"
    fi
done

print_success "Prerequisites setup complete! 🎉"

# =============================================================================
# PART 5: VNC SETUP (FINAL STEP)
# =============================================================================

print_status "Setting up VNC access..."

# # Set VNC password
# print_status "Setting VNC password (you'll be prompted)..."
# vncpasswd

# Start VNC server
print_status "Starting VNC server..."

# Check if VNC server is already running
if pgrep -f "Xtigervnc.*:1" > /dev/null || pgrep -f "vncserver.*:1" > /dev/null; then
    print_success "VNC server is already running on display :1"
    echo "   (Detected existing VNC process)"
else
    # Start VNC server with timeout to prevent hanging
    print_status "Attempting to start VNC server..."
    if timeout 10 vncserver :1 -geometry 2560x1400 -depth 24 -localhost yes 2>/dev/null; then
        print_success "VNC server started successfully"
    else
        print_warning "VNC server startup timed out or failed, but continuing..."
        echo "   (This is normal if VNC was already running)"
    fi
fi
echo ""
echo "🖥️  VNC Desktop Access:"
echo "   Start VNC: vncserver :1 -geometry 2560x1400 -depth 24 -localhost yes"
echo "   SSH Tunnel: ssh -i ~/.ssh/private.pem -L 5903:localhost:5901 ubuntu@<YOUR UBUNTU IP> -f -N"
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
echo "      ssh -i ~/.ssh/private.pem -L 5903:localhost:5901 ubuntu@<YOUR UBUNTU IP> -f -N"
echo "   This forwards your local port 5903 to the remote VNC server's port 5901."
echo "   Then connect your VNC client to localhost:5903."
echo ""
echo "   (Make sure to set up the SSH tunnel as shown above before connecting!)"
echo ""
echo "🔧 Git and GitHub CLI Setup:"
echo "   If git is not configured, run:"
echo "      git config --global user.name \"Your Name\""
echo "      git config --global user.email \"your.email@example.com\""
echo ""
echo "   To authenticate GitHub CLI, run:"
echo "      gh auth login"
echo "   This enables you to clone repositories, create issues, and manage GitHub resources from the command line."
echo ""
echo "======================================================================"
