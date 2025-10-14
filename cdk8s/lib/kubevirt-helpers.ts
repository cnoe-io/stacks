/**
 * KubeVirt Helper Library
 *
 * Provides reusable builder functions for VirtualMachine resources
 * to simplify VM creation with common patterns (cloud-init, resources, volumes)
 */

import { ApiObject } from 'cdk8s';

export interface VirtualMachineBuilderProps {
  name: string;
  namespace: string;

  // Run strategy (lifecycle management)
  runStrategy?: 'Always' | 'Manual' | 'Halted' | 'RerunOnFailure';

  // Resource allocation
  cpuCores?: number;
  memory?: string; // e.g., "4Gi"

  // Volume configuration
  volumes?: VolumeConfig[];

  // Network configuration
  networks?: NetworkConfig[];

  // Cloud-init configuration
  cloudInit?: CloudInitConfig;

  // Graphics configuration (enables VNC)
  enableGraphics?: boolean;

  // Additional labels and annotations
  labels?: { [key: string]: string };
  annotations?: { [key: string]: string };

  // Termination grace period (seconds)
  terminationGracePeriodSeconds?: number;
}

export interface VolumeConfig {
  name: string;
  type: 'dataVolume' | 'persistentVolumeClaim' | 'cloudInit';

  // For dataVolume or PVC volumes
  source?: string; // DataVolume or PVC name

  // For cloudInit volumes (use Secret for data > 2048 bytes)
  cloudInitData?: string;  // Inline cloud-init data (max 2048 bytes)
  cloudInitSecretName?: string;  // Secret reference for larger cloud-init data

  // Disk bus type (virtio, sata, scsi)
  bus?: string;
}

export interface NetworkConfig {
  name: string;
  type: 'pod' | 'multus';
  interfaceType?: 'masquerade' | 'bridge';
  // TCP/UDP ports to expose via masquerade (requires masquerade interface type)
  ports?: PortConfig[];
}

export interface PortConfig {
  name?: string;
  protocol?: 'TCP' | 'UDP';
  port: number;  // Port number in the guest VM
}

export interface CloudInitConfig {
  userData?: string; // Cloud-init user data (YAML string)
  secretName?: string; // Secret reference for cloud-init data
}

/**
 * Build a VirtualMachine resource with common configuration patterns
 *
 * @example
 * ```typescript
 * const vm = buildVirtualMachine(this, 'my-vm', {
 *   name: 'nixos-dev-vm',
 *   namespace: 'default',
 *   runStrategy: 'Manual',
 *   cpuCores: 2,
 *   memory: '4Gi',
 *   volumes: [{
 *     name: 'rootdisk',
 *     type: 'dataVolume',
 *     source: 'nixos-dev-datavolume',
 *     bus: 'virtio'
 *   }],
 *   cloudInit: {
 *     userData: `#cloud-config
 * hostname: nixos-dev
 * users:
 *   - name: vpittamp
 *     sudo: ALL=(ALL) NOPASSWD:ALL
 * `
 *   }
 * });
 * ```
 */
export function buildVirtualMachine(
  scope: any,
  id: string,
  props: VirtualMachineBuilderProps
): ApiObject {
  const {
    name,
    namespace,
    runStrategy = 'Manual',
    cpuCores = 2,
    memory = '4Gi',
    volumes = [],
    networks = [{ name: 'default', type: 'pod' }],
    cloudInit,
    enableGraphics = false,
    labels = {},
    annotations = {},
    terminationGracePeriodSeconds = 30,
  } = props;

  // Build disks array from volumes
  const disks = volumes.map((vol, index) => ({
    name: vol.name,
    disk: {
      bus: vol.bus || 'virtio',
    },
    // Set boot order for the first non-cloudInit volume
    ...(vol.type !== 'cloudInit' && index === 0 ? { bootOrder: 1 } : {}),
  }));

  // Build volumes array
  const volumeSpecs = volumes.map(vol => {
    if (vol.type === 'dataVolume' && vol.source) {
      return {
        name: vol.name,
        dataVolume: { name: vol.source },
      };
    } else if (vol.type === 'persistentVolumeClaim' && vol.source) {
      return {
        name: vol.name,
        persistentVolumeClaim: { claimName: vol.source },
      };
    } else if (vol.type === 'cloudInit') {
      return {
        name: vol.name,
        cloudInitNoCloud: vol.cloudInitSecretName
          ? { secretRef: { name: vol.cloudInitSecretName } }
          : vol.cloudInitData
          ? { userData: vol.cloudInitData }
          : cloudInit?.secretName
          ? { secretRef: { name: cloudInit.secretName } }
          : { userData: '' },
      };
    }
    throw new Error(`Invalid volume configuration: ${JSON.stringify(vol)}`);
  });

  // Build networks array
  const networkSpecs = networks.map(net => ({
    name: net.name,
    ...(net.type === 'pod' ? { pod: {} } : {}),
  }));

  // Build interfaces array with port configuration
  const interfaces = networks.map(net => {
    const baseInterface: any = { name: net.name };

    if (net.interfaceType === 'masquerade' || !net.interfaceType) {
      // Masquerade interface with optional port forwarding
      if (net.ports && net.ports.length > 0) {
        baseInterface.masquerade = {};
        baseInterface.ports = net.ports.map(p => ({
          ...(p.name ? { name: p.name } : {}),
          protocol: p.protocol || 'TCP',
          port: p.port,
        }));
      } else {
        baseInterface.masquerade = {};
      }
    } else if (net.interfaceType === 'bridge') {
      baseInterface.bridge = {};
    }

    return baseInterface;
  });

  const spec: any = {
    runStrategy,
    template: {
      metadata: {
        labels: {
          'kubevirt.io/domain': name,
          ...labels,
        },
        annotations,
      },
      spec: {
        domain: {
          resources: {
            requests: {
              memory,
              cpu: `${cpuCores}`,
            },
          },
          devices: {
            disks,
            interfaces: interfaces.length > 0 ? interfaces : undefined,
            ...(enableGraphics ? {
              autoattachGraphicsDevice: true,
              inputs: [{
                type: 'tablet',
                bus: 'usb',
                name: 'tablet'
              }]
            } : {}),
          },
        },
        networks: networkSpecs.length > 0 ? networkSpecs : undefined,
        volumes: volumeSpecs,
        terminationGracePeriodSeconds,
      },
    },
  };

  return new ApiObject(scope, id, {
    apiVersion: 'kubevirt.io/v1',
    kind: 'VirtualMachine',
    metadata: {
      name,
      namespace,
      labels: {
        'app.kubernetes.io/name': name,
        ...labels,
      },
      annotations,
    },
    spec,
  });
}

/**
 * Build cloud-init user data for NixOS VMs
 *
 * @param hostname - VM hostname
 * @param username - Primary user name
 * @param sshKeys - SSH authorized keys (optional)
 * @param password - Plain text password (will be set via chpasswd)
 */
export function buildCloudInitUserData(
  hostname: string,
  username: string,
  sshKeys?: string[],
  password?: string,
  installDesktop: boolean = false
): string {
  // Generate proper YAML format, not JSON
  let userData = `#cloud-config
hostname: ${hostname}
users:
  - name: ${username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash`;

  if (sshKeys && sshKeys.length > 0) {
    userData += '\n    ssh_authorized_keys:';
    sshKeys.forEach(key => {
      userData += `\n      - ${key}`;
    });
  }

  // Use chpasswd to set passwords (works with plain text)
  // This is the proper way to set passwords in cloud-init
  if (password) {
    userData += `\nchpasswd:
  list: |
    ${username}:${password}
    root:${password}
  expire: false`;
  }

  // Install desktop environment and xrdp for remote desktop access
  if (installDesktop) {
    userData += `
runcmd:
  # Configure minimal NixOS base with desktop, remote access, and dev tools
  - |
    cat > /etc/nixos/configuration.nix <<'NIXEOF'
    { config, pkgs, ... }:
    {
      imports = [ /etc/nixos/hardware-configuration.nix ];

      # Networking
      networking.hostName = "${hostname}";
      networking.networkmanager.enable = true;

      # SSH - CRITICAL for remote management
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true;
          PermitRootLogin = "no";
        };
      };

      # KDE Plasma 6 Desktop Environment
      services.desktopManager.plasma6.enable = true;
      services.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
      };

      # Remote Desktop Protocol (xrdp)
      services.xrdp = {
        enable = true;
        defaultWindowManager = "startplasma-x11";
        openFirewall = true;
      };

      # Firewall - open all remote access ports
      networking.firewall.allowedTCPPorts = [ 22 3389 5900 5901 ];

      # Audio support
      hardware.pulseaudio.enable = true;

      # User configuration
      users.users.${username} = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
        shell = pkgs.bash;
      };

      # Security - allow sudo without password for wheel group
      security.sudo.wheelNeedsPassword = false;

      # Allow unfree packages (some tools require this)
      nixpkgs.config.allowUnfree = true;

      # Essential system packages - keep minimal
      environment.systemPackages = with pkgs; [
        # Core utilities
        wget curl vim git htop tmux
        # Desktop apps
        firefox
        # Remote access
        tigervnc
        # NixOS management
        home-manager nixos-rebuild
      ];

      # Nix configuration
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      system.stateVersion = "24.05";
    }
    NIXEOF
  # Rebuild NixOS with base configuration (fast: ~2 minutes)
  - nixos-rebuild switch
  # Ensure critical services are running
  - systemctl enable sshd && systemctl start sshd
  - systemctl enable xrdp && systemctl start xrdp
  # Set up VNC server for user
  - su - ${username} -c "mkdir -p ~/.vnc"
  - su - ${username} -c "echo '${password}' | vncpasswd -f > ~/.vnc/passwd"
  - su - ${username} -c "chmod 600 ~/.vnc/passwd"
  - |
    cat > /home/${username}/.vnc/xstartup <<'VNCEOF'
    #!/bin/sh
    unset SESSION_MANAGER
    unset DBUS_SESSION_BUS_ADDRESS
    exec startplasma-x11
    VNCEOF
  - chmod +x /home/${username}/.vnc/xstartup
  - chown ${username}:users /home/${username}/.vnc/xstartup
  # VNC systemd service
  - |
    cat > /etc/systemd/system/vncserver@.service <<'SYSTEMDEOF'
    [Unit]
    Description=VNC Server for Display %i
    After=network.target

    [Service]
    Type=forking
    User=${username}
    ExecStart=/run/current-system/sw/bin/vncserver :%i -geometry 1920x1080 -depth 24
    ExecStop=/run/current-system/sw/bin/vncserver -kill :%i
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target
    SYSTEMDEOF
  - systemctl daemon-reload
  - systemctl enable vncserver@1.service
  - systemctl start vncserver@1.service
  # Clone user's nixos-config repository
  - su - ${username} -c "git clone https://github.com/vpittamp/nixos-config ~/nixos-config 2>/dev/null || echo 'nixos-config already exists or failed to clone'"
  # Create convenience script to apply full user configuration
  - |
    cat > /home/${username}/apply-my-nixos-config.sh <<'APPLYEOF'
    #!/bin/bash
    # One-command setup: apply your full nixos-config
    set -e

    echo "=== Applying vpittamp nixos-config ==="

    # Update the repo
    cd ~/nixos-config
    git pull

    # Backup current system config
    sudo cp /etc/nixos/configuration.nix /etc/nixos/configuration.nix.vm-base-backup

    # Check if using flakes
    if [ -f "flake.nix" ]; then
      echo "Detected flake.nix - applying with flakes..."
      # You'll need to specify your host name here
      read -p "Enter your flake host name (e.g., nixos-dev-vm): " FLAKE_HOST
      sudo nixos-rebuild switch --flake ".#\${FLAKE_HOST}"
    elif [ -f "configuration.nix" ]; then
      echo "Detected configuration.nix - applying traditional config..."
      sudo cp configuration.nix /etc/nixos/configuration.nix
      sudo nixos-rebuild switch
    else
      echo "ERROR: No configuration.nix or flake.nix found!"
      echo "Please manually configure your system."
      exit 1
    fi

    # Apply home-manager if configured
    if [ -f "home.nix" ] || [ -f "home-manager/home.nix" ]; then
      echo "Applying home-manager configuration..."
      home-manager switch
    fi

    echo ""
    echo "=== Configuration applied successfully! ==="
    echo "You may need to log out and back in for all changes to take effect."
    APPLYEOF
  - chmod +x /home/${username}/apply-my-nixos-config.sh
  - chown ${username}:users /home/${username}/apply-my-nixos-config.sh
  # Create helpful README
  - |
    cat > /home/${username}/README-FIRST.txt <<'READMEEOF'
    Welcome to your NixOS Development VM!
    ======================================

    This VM has a base configuration with:
    - SSH, RDP, VNC remote access
    - KDE Plasma 6 desktop environment
    - Essential development tools
    - Your nixos-config repository cloned at ~/nixos-config

    To apply your FULL nixos-config:
    ---------------------------------
    1. SSH into this VM or open a terminal
    2. Run: ./apply-my-nixos-config.sh
    3. Follow the prompts
    4. Log out and back in

    Remote Access:
    --------------
    - SSH:  ssh -p 2222 vpittamp@100.87.204.44 (via port-forward)
    - RDP:  100.87.204.44:33389 (via port-forward)
    - VNC:  Port-forward 5901 then connect to localhost:5901

    Default credentials: ${username} / ${password}

    Your configuration repo: ~/nixos-config
    READMEEOF
  - chown ${username}:users /home/${username}/README-FIRST.txt`;
  }

  return userData;
}

/**
 * Build dataVolumeTemplates for ephemeral VM disks
 * (PVCs owned by VM, deleted when VM deleted)
 *
 * @example
 * ```typescript
 * const vm = new VirtualMachine(this, 'vm', {
 *   spec: {
 *     dataVolumeTemplates: buildDataVolumeTemplates({
 *       name: 'my-vm-disk',
 *       imageUrl: 'http://image-server/nixos.qcow2',
 *       storageSize: '20Gi'
 *     }),
 *     // ... rest of VM spec
 *   }
 * });
 * ```
 */
export function buildDataVolumeTemplates(props: {
  name: string;
  imageUrl: string;
  storageSize?: string;
  storageClassName?: string;
}): any[] {
  return [
    {
      metadata: { name: props.name },
      spec: {
        source: {
          http: { url: props.imageUrl },
        },
        pvc: {
          accessModes: ['ReadWriteOnce'],
          resources: {
            requests: {
              storage: props.storageSize || '20Gi',
            },
          },
          ...(props.storageClassName ? { storageClassName: props.storageClassName } : {}),
        },
      },
    },
  ];
}
