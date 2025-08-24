## Minimal Nix shell configuration
let
  pkgs = import <nixpkgs> {};
  
  # Custom Neovim with claude-code plugin
  customNeovim = pkgs.neovim.override {
    configure = {
      packages.myPlugins = with pkgs.vimPlugins; {
        start = [ 
          claude-code-nvim
        ];
      };
      customRC = ''
        " Claude Code plugin is available
        " You can configure it here if needed
      '';
    };
  };
in
pkgs.mkShell {
  buildInputs = with pkgs; builtins.filter (x: x != null) [
    # Core development tools
    python3 gnumake gcc curl git cacert coreutils
    stdenv.cc binutils linuxHeaders

    # Terminal and editor tools
    tmux fzf customNeovim ripgrep fd bat eza vivid sesh zoxide yazi

    # Node.js ecosystem
    nodejs pnpm yarn
    nodePackages.npm
    nodePackages.typescript
    nodePackages.concurrently
    nodePackages.nodemon

    # Container and Kubernetes tools
    kubectl
    (if pkgs ? kubernetes-helm then kubernetes-helm else (if pkgs ? helm then helm else null))
    kind k3d argocd argo vcluster
    (if pkgs ? devspace then devspace else null)

    # Development tools
    gh go golangci-lint jq
    (if pkgs ? yq-go then yq-go else (if pkgs ? yq then yq else null))
    step-cli cmake gnupg pkg-config openssl libxml2

    # Network tools
    iputils iproute2
    (if pkgs ? netcat then netcat else (if pkgs ? netcat-openbsd then netcat-openbsd else (if pkgs ? gnu-netcat then gnu-netcat else null)))
    bind dnsutils

    # Cloud CLIs
    azure-cli
    (if builtins.hasAttr "1password-cli" pkgs then pkgs."1password-cli" else null)

    # Other utilities
    act xh watchman direnv ncurses
    (if pkgs ? nodePackages && pkgs.nodePackages ? cdk8s-cli then pkgs.nodePackages.cdk8s-cli else null)
  ];

  shellHook = ''
    # Azure/Workload Identity Configuration
    export APP_ID="1140d9c2-62f6-4857-94c2-7e0e6c64e562"
    export AZURE_TENANT_ID="0c4da9c5-40ea-4e7d-9c7a-e7308d4f8e38"
    export AZURE_SUBSCRIPTION_ID="fa5b32b6-1d6d-4110-bea2-8ac0e3126a38"
    export AZURE_STORAGE_ACCOUNT="oidcissuer65846b7df97b"
    export RESOURCE_GROUP="rg4"
    export SERVICE_ACCOUNT_ISSUER="https://oidcissuer65846b7df97b.z13.web.core.windows.net/"
    export ACR_NAME="vpittamp"
    export ACR_RG="rg3"
    export AZURE_KEYVAULT_NAME="keyvault-thcmfmoo5oeow"
    export CLUSTER_NAME="kind"
    export AZURE_CLIENT_ID="1140d9c2-62f6-4857-94c2-7e0e6c64e562"
    export GH_APP_ID="1272071"
    export GH_INSTALLATION_ID="66754705"

    # Environment Configuration
    export ENVIRONMENT="dev"
    export CLUSTER_TYPE="kind"
    export NODE_ENV="dev"

    # Ingress Configuration
    export ENABLE_TLS="true"
    export TLS_ISSUER=""
    export INGRESS_HOST="cnoe.localtest.me"
    export NEXTJS_BASE_URL="https://chat.cnoe.localtest.me"

    # Let's Encrypt Configuration
    export ACME_EMAIL="admin@ai401kchat.com"

    # Backstage Configuration
    export AUTH_ENVIRONMENT="development"
    export K8S_CLUSTER_NAME="kind"
    export ARGOCD_API_URL="http://argocd-server.argocd:80/api/v1/"
    export BACKSTAGE_BASE_URL="http://localhost:7007"
    export BACKEND_BASE_URL="http://localhost:7007"

    # Neon Database Configuration
    export POSTGRES_HOST="ep-wild-heart-a8c6ysmx-pooler.eastus2.azure.neon.tech"
    export POSTGRES_PORT="5432"
    export POSTGRES_USER="neondb_owner"
    export POSTGRES_DATABASE="neondb"
    export POSTGRES_SSL_MODE="require"
    export POSTGRES_CHANNEL_BINDING="require"

    export EXTERNAL_URL="https://ai-platform-engineering.cnoe.localtest.me:8443"

    echo "Environment variables loaded from .env-files/wi.env"
    
    # Configure yazi with vscode-dark-modern theme
    mkdir -p ~/.config/yazi
    cat > ~/.config/yazi/theme.toml << 'EOF'
# VSCode Dark Modern theme for Yazi
[manager]
cwd = { fg = "#569cd6" }

# Hovered
hovered         = { fg = "#000000", bg = "#b8d7f3" }
preview_hovered = { underline = true }

# Find
find_keyword  = { fg = "#f9826c", italic = true }
find_position = { fg = "#cccccc", bg = "#3a3f4b", italic = true }

# Marker
marker_selected = { fg = "#b8d7f3", bg = "#3c5d80" }
marker_copied   = { fg = "#b8d7f3", bg = "#487844" }
marker_cut      = { fg = "#b8d7f3", bg = "#d47766" }

# Tab
tab_active   = { fg = "#000000", bg = "#569cd6" }
tab_inactive = { fg = "#cccccc", bg = "#3c3c3c" }
tab_width    = 1

# Border
border_symbol = "│"
border_style  = { fg = "#3e3e3e" }

# Highlighting
syntect_theme = "~/.config/yazi/VSCode-Dark-Modern.tmTheme"

[status]
separator_style     = { fg = "#4e4e4e", bg = "#252526" }
mode_normal         = { fg = "#000000", bg = "#569cd6", bold = true }
mode_select         = { fg = "#000000", bg = "#c586c0", bold = true }
mode_unset          = { fg = "#000000", bg = "#d7ba7d", bold = true }

progress_label      = { fg = "#ffffff", bold = true }
progress_normal     = { fg = "#569cd6", bg = "#252526" }
progress_error      = { fg = "#f44747", bg = "#252526" }

permissions_t = { fg = "#569cd6" }
permissions_r = { fg = "#d7ba7d" }
permissions_w = { fg = "#f44747" }
permissions_x = { fg = "#b5cea8" }
permissions_s = { fg = "#c586c0" }

[input]
border   = { fg = "#569cd6" }
title    = {}
value    = {}
selected = { reversed = true }

[select]
border   = { fg = "#569cd6" }
active   = { fg = "#c586c0" }
inactive = {}

[tasks]
border  = { fg = "#569cd6" }
title   = {}
hovered = { underline = true }

[which]
mask            = { bg = "#1e1e1e" }
cand            = { fg = "#9cdcfe" }
rest            = { fg = "#808080" }
desc            = { fg = "#c586c0" }
separator       = " "
separator_style = { fg = "#4e4e4e" }

[help]
on      = { fg = "#c586c0" }
exec    = { fg = "#9cdcfe" }
desc    = { fg = "#808080" }
hovered = { bg = "#3c5d80", bold = true }
footer  = { fg = "#252526", bg = "#cccccc" }

[filetype]

rules = [
  # Images
  { mime = "image/*", fg = "#c586c0" },
  
  # Videos
  { mime = "video/*", fg = "#d7ba7d" },
  
  # Audio
  { mime = "audio/*", fg = "#d7ba7d" },
  
  # Archives
  { mime = "application/zip",             fg = "#f14c4c" },
  { mime = "application/gzip",            fg = "#f14c4c" },
  { mime = "application/x-tar",           fg = "#f14c4c" },
  { mime = "application/x-bzip",          fg = "#f14c4c" },
  { mime = "application/x-bzip2",         fg = "#f14c4c" },
  { mime = "application/x-7z-compressed", fg = "#f14c4c" },
  { mime = "application/x-rar",           fg = "#f14c4c" },
  
  # Fallback
  { name = "*", fg = "#cccccc" },
  { name = "*/", fg = "#569cd6" }
]

[icon]

rules = [
  # Programming
  { name = "*.c",     text = "" },
  { name = "*.cpp",   text = "" },
  { name = "*.h",     text = "" },
  { name = "*.hpp",   text = "" },
  { name = "*.rs",    text = "" },
  { name = "*.go",    text = "" },
  { name = "*.py",    text = "" },
  { name = "*.js",    text = "" },
  { name = "*.jsx",   text = "⚛" },
  { name = "*.ts",    text = "" },
  { name = "*.tsx",   text = "⚛" },
  { name = "*.vue",   text = "﵂" },
  { name = "*.json",  text = "" },
  { name = "*.toml",  text = "" },
  { name = "*.yaml",  text = "" },
  { name = "*.yml",   text = "" },
  { name = "*.nix",   text = "" },
  
  # Text
  { name = "*.txt",   text = "" },
  { name = "*.md",    text = "" },
  
  # Archives
  { name = "*.zip",   text = "" },
  { name = "*.tar",   text = "" },
  { name = "*.gz",    text = "" },
  { name = "*.7z",    text = "" },
  { name = "*.bz2",   text = "" },
  
  # Default
  { name = "*",       text = "" },
  { name = "*/",      text = "" },
]
EOF
  '';
}