import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * Props for K8sApiTailscaleServeChart
 */
export interface K8sApiTailscaleServeChartProps extends ChartProps {
  /**
   * Service name for Tailscale Services registration
   * @default 'k8s-api'
   */
  serviceName?: string;

  /**
   * Kubernetes namespace for deployment
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Name of the secret containing the Tailscale auth key
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Tailscale container image
   * @default 'tailscale/tailscale:latest'
   */
  tailscaleImage?: string;

  /**
   * kubectl container image
   * @default 'bitnami/kubectl:latest'
   */
  kubectlImage?: string;

  /**
   * Tailnet name for generating kubeconfig instructions
   * @default 'tail286401'
   */
  tailnetName?: string;

  /**
   * Whether to create a static token secret for remote access
   * When true, creates a Secret that can be used with ExternalSecrets
   * to maintain a stable token across cluster recreations
   * @default true
   */
  createStaticTokenSecret?: boolean;

  /**
   * Name of the secret containing the static remote access token
   * This secret should be synced from Azure Key Vault via ExternalSecrets
   * @default 'k8s-remote-access-token'
   */
  remoteAccessTokenSecretName?: string;
}

/**
 * Expose Kubernetes API via Tailscale Services for remote kubectl access.
 *
 * This chart creates a deployment with:
 * 1. Tailscale container running in userspace mode with --service flag
 * 2. kubectl-proxy sidecar providing API access
 *
 * The kubectl proxy runs on port 8001 internally, but Tailscale serves it
 * on HTTPS port 443 with automatic TLS.
 *
 * Access: https://k8s-api.<tailnet>.ts.net/api/v1/...
 *
 * For stable remote access across cluster recreations:
 * 1. Store a static token in Azure Key Vault (K8S-REMOTE-ACCESS-TOKEN)
 * 2. The ExternalSecret syncs it to k8s-remote-access-token secret
 * 3. Use the kubeconfig template from the ConfigMap
 *
 * Usage:
 *   kubectl --kubeconfig=~/.kube/tailscale-cluster.yaml get pods
 */
export class K8sApiTailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props?: K8sApiTailscaleServeChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace ?? 'tailscale';
    const serviceName = props?.serviceName ?? 'k8s-api';
    const authKeySecretName = props?.authKeySecretName ?? 'tailscale-auth-key';
    const tailscaleImage = props?.tailscaleImage ?? 'tailscale/tailscale:latest';
    const kubectlImage = props?.kubectlImage ?? 'bitnami/kubectl:latest';
    const tailnetName = props?.tailnetName ?? 'tail286401';
    const createStaticTokenSecret = props?.createStaticTokenSecret ?? true;
    const remoteAccessTokenSecretName = props?.remoteAccessTokenSecretName ?? 'k8s-remote-access-token';

    const deploymentName = 'k8s-api-tailscale-serve';
    const serviceAccountName = 'k8s-api-serve';

    // ServiceAccount for API access (used by kubectl-proxy)
    new k8s.KubeServiceAccount(this, 'sa', {
      metadata: {
        name: serviceAccountName,
        namespace,
      },
    });

    // ClusterRoleBinding for cluster-admin access
    new k8s.KubeClusterRoleBinding(this, 'crb', {
      metadata: {
        name: 'k8s-api-tailscale-serve',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'cluster-admin',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccountName,
          namespace,
        },
      ],
    });

    // ServiceAccount for remote access (token stored in Key Vault)
    const remoteServiceAccountName = 'k8s-remote-access';
    new k8s.KubeServiceAccount(this, 'remote-sa', {
      metadata: {
        name: remoteServiceAccountName,
        namespace,
        annotations: {
          'description': 'ServiceAccount for remote kubectl access via Tailscale',
        },
      },
    });

    // ClusterRoleBinding for remote access ServiceAccount
    new k8s.KubeClusterRoleBinding(this, 'remote-crb', {
      metadata: {
        name: 'k8s-remote-access',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'cluster-admin',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: remoteServiceAccountName,
          namespace,
        },
      ],
    });

    // ConfigMap with kubeconfig template for remote access
    // Users can copy this and add their token from Key Vault
    if (createStaticTokenSecret) {
      const kubeconfigTemplate = `apiVersion: v1
kind: Config
clusters:
- name: tailscale-cluster
  cluster:
    server: https://${serviceName}.${tailnetName}.ts.net
contexts:
- name: tailscale-cluster
  context:
    cluster: tailscale-cluster
    user: tailscale-admin
current-context: tailscale-cluster
users:
- name: tailscale-admin
  user:
    # Token is stored in Azure Key Vault: K8S-REMOTE-ACCESS-TOKEN
    # Retrieve with: az keyvault secret show --vault-name <vault> --name K8S-REMOTE-ACCESS-TOKEN --query value -o tsv
    token: <TOKEN_FROM_KEY_VAULT>
`;

      new k8s.KubeConfigMap(this, 'kubeconfig-template', {
        metadata: {
          name: 'k8s-remote-kubeconfig-template',
          namespace,
          labels: {
            'app.kubernetes.io/name': 'k8s-remote-access',
            'app.kubernetes.io/component': 'kubeconfig',
          },
        },
        data: {
          'kubeconfig.yaml': kubeconfigTemplate,
          'README.md': `# Remote Kubernetes Access via Tailscale

## Setup Instructions

1. Ensure you're connected to Tailscale on your remote machine

2. Get the token from Azure Key Vault:
   \`\`\`bash
   az keyvault secret show --vault-name <your-vault> --name K8S-REMOTE-ACCESS-TOKEN --query value -o tsv
   \`\`\`

3. Create your kubeconfig file on your remote machine:
   \`\`\`bash
   mkdir -p ~/.kube
   cat > ~/.kube/tailscale-cluster.yaml << 'EOF'
   apiVersion: v1
   kind: Config
   clusters:
   - name: tailscale-cluster
     cluster:
       server: https://${serviceName}.${tailnetName}.ts.net
   contexts:
   - name: tailscale-cluster
     context:
       cluster: tailscale-cluster
       user: tailscale-admin
   current-context: tailscale-cluster
   users:
   - name: tailscale-admin
     user:
       token: <PASTE_TOKEN_HERE>
   EOF
   \`\`\`

4. Test the connection:
   \`\`\`bash
   kubectl --kubeconfig=~/.kube/tailscale-cluster.yaml get nodes
   \`\`\`

## One-Time Token Generation

If K8S-REMOTE-ACCESS-TOKEN doesn't exist in Key Vault, generate it:
\`\`\`bash
# On the cluster host
TOKEN=$(kubectl create token k8s-remote-access -n tailscale --duration=8760h)

# Store in Azure Key Vault
az keyvault secret set --vault-name <your-vault> --name K8S-REMOTE-ACCESS-TOKEN --value "$TOKEN"
\`\`\`

Note: The token is valid for 1 year. Regenerate before expiration.
`,
        },
      });
    }

    // Deployment with Tailscale + kubectl-proxy
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: deploymentName,
        namespace,
        labels: {
          'app.kubernetes.io/name': deploymentName,
          'app.kubernetes.io/part-of': 'kubernetes',
          'app.kubernetes.io/component': 'api-proxy',
        },
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: { 'app.kubernetes.io/name': deploymentName } },
        template: {
          metadata: {
            labels: { 'app.kubernetes.io/name': deploymentName },
          },
          spec: {
            serviceAccountName: 'k8s-api-serve',
            // Init container waits for secret to exist before starting main containers
            // This prevents CreateContainerConfigError when ESO hasn't synced yet
            initContainers: [
              {
                name: 'wait-for-secret',
                image: kubectlImage,
                command: ['/bin/sh', '-c'],
                args: [`
echo "Waiting for secret ${authKeySecretName} to exist..."
while ! kubectl get secret ${authKeySecretName} -n ${namespace} > /dev/null 2>&1; do
  echo "Secret not found, waiting 5s..."
  sleep 5
done
echo "Secret ${authKeySecretName} found, proceeding..."
`],
              },
            ],
            containers: [
              {
                name: 'tailscale-serve',
                image: tailscaleImage,
                securityContext: {
                  runAsNonRoot: false,
                  privileged: false,
                },
                env: [
                  {
                    name: 'TS_AUTHKEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: authKeySecretName,
                        key: 'authKey',
                      },
                    },
                  },
                ],
                command: ['/bin/sh', '-c'],
                args: [generateK8sApiServeScript(serviceName)],
                ports: [
                  { name: 'https', containerPort: 443 },
                ],
              },
              {
                name: 'kubectl-proxy',
                image: kubectlImage,
                command: [
                  'kubectl',
                  'proxy',
                  '--port=8001',
                  '--address=0.0.0.0',
                  '--accept-hosts=.*',
                  '--reject-paths=^$',
                ],
                ports: [
                  { name: 'http', containerPort: 8001 },
                ],
                livenessProbe: {
                  httpGet: {
                    path: '/healthz',
                    port: k8s.IntOrString.fromNumber(8001),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/healthz',
                    port: k8s.IntOrString.fromNumber(8001),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                },
              },
            ],
          },
        },
      },
    });
  }
}

/**
 * Generate the shell script for the K8s API Tailscale serve container.
 *
 * Note: In userspace networking mode with Tailscale Services, netstack routes
 * incoming traffic to the exposed port (443), not the configured backend port.
 * We use socat to forward from 443 -> 8001 (kubectl-proxy).
 */
function generateK8sApiServeScript(serviceName: string): string {
  return `
set -euo pipefail

# start tailscaled in userspace mode (no TUN device needed)
mkdir -p /var/lib/tailscale
tailscaled --tun=userspace-networking \\
  --socket=/run/tailscale/tailscaled.sock \\
  --state=/var/lib/tailscale/tailscaled.state &

# install socat for port forwarding (required for userspace networking + Services)
apk add --no-cache socat >/dev/null

# wait for tailscaled to come up
for i in $(seq 1 40); do
  tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1 && break
  sleep 0.5
done

# bring the node up (no DNS/routes/ssh)
tailscale --socket=/run/tailscale/tailscaled.sock up \\
  --authkey="$TS_AUTHKEY" \\
  --accept-dns=false --accept-routes=false --ssh=false

# wait for kubectl-proxy to be ready
for i in $(seq 1 30); do
  wget -q -O /dev/null http://127.0.0.1:8001/healthz && break
  sleep 1
done

# Start socat to forward from exposed port (443) to kubectl-proxy (8001)
# This is required because netstack in userspace mode routes to the exposed port
socat TCP-LISTEN:443,fork,reuseaddr TCP:127.0.0.1:8001 &

# expose kubectl-proxy via tailscale serve on HTTPS 443
# The serve command tells Tailscale to route traffic to localhost:443 (socat)
tailscale --socket=/run/tailscale/tailscaled.sock \\
  serve --service=svc:${serviceName} --https=443 http://127.0.0.1:443

echo "Kubernetes API proxy running at https://${serviceName}.<tailnet>.ts.net"
exec tail -f /dev/null
`;
}
