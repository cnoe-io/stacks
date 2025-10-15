/**
 * NixOsVmCloudInitSecretsChart - Generates cloud-init Secret with secrets from Azure Key Vault
 *
 * This chart creates an ExternalSecret that:
 * 1. Pulls Tailscale auth key and RustDesk password from Azure Key Vault
 * 2. Generates a complete cloud-init userdata YAML using templates
 * 3. Creates a Kubernetes Secret ready for KubeVirt VM consumption
 *
 * This is the production-ready approach: secrets never leave Kubernetes, fully GitOps-compatible.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

export interface NixOsVmCloudInitSecretsChartProps extends ChartProps {
  /**
   * Target namespace for the secret
   * @default "default"
   */
  namespace?: string;

  /**
   * VM name (used for hostname and secret naming)
   * @default "nixos-dev-vm"
   */
  vmName?: string;

  /**
   * Primary username for the VM
   * @default "vpittamp"
   */
  username?: string;

  /**
   * SSH public keys (array of keys)
   * @default ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAq4r867qHnS9YUMbu+X7i40sfWZmkdymioHFmtewegC k8s_ed_test"]
   */
  sshKeys?: string[];

  /**
   * Console password (plain text, will be hashed by cloud-init)
   * @default "nixos123"
   */
  consolePassword?: string;

  /**
   * Enable Tailscale auto-authentication
   * @default true
   */
  enableTailscale?: boolean;

  /**
   * Enable RustDesk remote desktop
   * @default true
   */
  enableRustDesk?: boolean;

  /**
   * PATH to set for runcmd scripts in NixOS
   * @default "/run/current-system/sw/bin:/run/wrappers/bin:$PATH"
   * @remarks NixOS system binaries are in /run/current-system/sw/bin
   */
  nixosSystemPath?: string;

  /**
   * ArgoCD sync wave for secret creation
   * @default "5"
   */
  syncWave?: string;
}

export class NixOsVmCloudInitSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsVmCloudInitSecretsChartProps = {}) {
    super(scope, id, props);

    const {
      namespace = 'default',
      vmName = 'nixos-dev-vm',
      username = 'vpittamp',
      sshKeys = ['ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAq4r867qHnS9YUMbu+X7i40sfWZmkdymioHFmtewegC k8s_ed_test'],
      consolePassword = 'nixos123',
      enableTailscale = true,
      enableRustDesk = true,
      nixosSystemPath = '/run/current-system/sw/bin:/run/wrappers/bin:$PATH',
      syncWave = '5',
    } = props;

    // Build SSH keys YAML list
    const sshKeysYaml = sshKeys.map(key => `      - ${key}`).join('\n');

    // Build cloud-init template with secret placeholders
    // External Secrets will replace {{ .tailscale_auth_key }} and {{ .rustdesk_password }}
    const cloudInitTemplate = `#cloud-config
hostname: ${vmName}
users:
  - name: ${username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /run/current-system/sw/bin/bash
    ssh_authorized_keys:
${sshKeysYaml}
chpasswd:
  list: |
    ${username}:${consolePassword}
    root:${consolePassword}
  expire: false
runcmd:${enableTailscale ? `
  # Tailscale authentication with auth key from Azure Key Vault
  - |
    # Set PATH for NixOS (system binaries are in /run/current-system/sw/bin)
    export PATH="${nixosSystemPath}"
    # Wait for tailscaled to be ready
    timeout 30 sh -c 'until tailscale status 2>&1 | grep -q "Logged out\\\\|100\\\\."; do sleep 1; done'
    echo "Authenticating Tailscale with auth key from Azure Key Vault..."
    tailscale up --authkey="{{ .tailscale_auth_key }}" --ssh --advertise-tags=tag:vm && \\
      echo "✓ Tailscale authenticated successfully" || \\
      echo "✗ Tailscale authentication failed"` : ''}${enableRustDesk ? `
  # Configure RustDesk permanent password from Azure Key Vault
  - |
    # Set PATH for NixOS
    export PATH="${nixosSystemPath}"
    echo "Setting RustDesk permanent password from Azure Key Vault..."
    mkdir -p /root/.config/rustdesk
    if [ -f /root/.config/rustdesk/RustDesk2.toml ]; then
      # Update existing config
      if grep -q "permanent-password" /root/.config/rustdesk/RustDesk2.toml; then
        sed -i 's/^permanent-password = .*/permanent-password = "{{ .rustdesk_password }}"/' /root/.config/rustdesk/RustDesk2.toml
      else
        echo 'permanent-password = "{{ .rustdesk_password }}"' >> /root/.config/rustdesk/RustDesk2.toml
      fi
    else
      # Create minimal config with permanent password
      cat > /root/.config/rustdesk/RustDesk2.toml <<'RUSTDESK_CONFIG_EOF'
    [options]
    permanent-password = "{{ .rustdesk_password }}"
    allow-linux-headless = "Y"
    direct-server = "Y"
    direct-access-port = "21116"
    RUSTDESK_CONFIG_EOF
    fi
    # Restart RustDesk service to apply password
    systemctl restart rustdesk 2>/dev/null || systemctl restart rustdesk-headless 2>/dev/null || true
    echo "✓ RustDesk password configured from Azure Key Vault"
    # Save RustDesk connection info for user
    echo "RustDesk Password: {{ .rustdesk_password }}" > /root/rustdesk-info.txt
    chmod 600 /root/rustdesk-info.txt` : ''}
`;

    // ExternalSecret that generates cloud-init with secrets from Azure Key Vault
    new ExternalSecret(this, 'vm-cloudinit-secrets', {
      metadata: {
        name: `${vmName}-cloudinit`,
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app': vmName,
          'component': 'cloud-init',
          'managed-by': 'external-secrets',
        },
      },
      spec: {
        refreshInterval: '1h',  // Refresh hourly for secret rotation
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: `${vmName}-cloudinit`,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app': vmName,
                'component': 'cloud-init',
                'managed-by': 'external-secrets',
              },
            },
            data: {
              // Cloud-init userdata with secrets injected via template
              'userdata': cloudInitTemplate,
            },
          },
        },
        data: [
          {
            secretKey: 'tailscale_auth_key',
            remoteRef: {
              key: 'TAILSCALE-VM-AUTH-KEY',
            },
          },
          {
            secretKey: 'rustdesk_password',
            remoteRef: {
              key: 'RUSTDESK-PASSWORD',
            },
          },
        ],
      },
    });
  }
}
