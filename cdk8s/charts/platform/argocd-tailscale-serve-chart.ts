import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * Expose ArgoCD over Tailscale using tailscale serve (userspace, no TUN).
 * Uses existing secret tailscale-auth-key in the tailscale namespace.
 */
export class ArgoCdTailscaleServeChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const namespace = 'tailscale';
    const name = 'argocd-tailscale-serve';
    const hostname = 'argocd-ui-serve';

    new k8s.KubeDeployment(this, 'ts-serve-deployment', {
      metadata: {
        name,
        namespace,
        labels: {
          'app.kubernetes.io/name': name,
          'app.kubernetes.io/part-of': 'argocd',
        },
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: { 'app.kubernetes.io/name': name } },
        template: {
          metadata: {
            labels: { 'app.kubernetes.io/name': name },
          },
          spec: {
            automountServiceAccountToken: false,
            containers: [
              {
                name: 'tailscale-serve',
                image: 'tailscale/tailscale:latest',
                securityContext: {
                  runAsNonRoot: false,
                  privileged: false,
                },
                env: [
                  {
                    name: 'TS_AUTHKEY',
                    valueFrom: {
                      secretKeyRef: { name: 'tailscale-auth-key', key: 'authKey' },
                    },
                  },
                  { name: 'TS_HOSTNAME', value: hostname },
                ],
                command: ['/bin/sh', '-c'],
                args: [
`
set -euo pipefail

# start tailscaled in userspace mode (no TUN device needed)
mkdir -p /var/lib/tailscale
tailscaled --tun=userspace-networking \
  --socket=/run/tailscale/tailscaled.sock \
  --state=/var/lib/tailscale/tailscaled.state &

# install lightweight TCP proxy to keep backend on localhost (required by new tailscale serve)
apk add --no-cache socat >/dev/null
PORT_FWD=8443
socat TCP-LISTEN:\${PORT_FWD},fork,reuseaddr TCP:argocd-server.argocd.svc.cluster.local:443 &

# wait for tailscaled to come up
for i in $(seq 1 40); do
  tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1 && break
  sleep 0.5
done

# bring the node up (no DNS/routes/ssh)
tailscale --socket=/run/tailscale/tailscaled.sock up \
  --authkey="$TS_AUTHKEY" \
  --hostname="$TS_HOSTNAME" \
  --accept-dns=false --accept-routes=false --ssh=false

# expose ArgoCD via tailscale serve (tailscale handles HTTPS cert)
tailscale --socket=/run/tailscale/tailscaled.sock \
  serve --bg https://127.0.0.1:\${PORT_FWD}

echo "tailscale serve running for ArgoCD at $TS_HOSTNAME"
exec tail -f /dev/null
`
                ],
                ports: [
                  { name: 'peerapi', containerPort: 443 },
                ],
              },
            ],
          },
        },
      },
    });
  }
}
