import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

interface HostSpec { name: string; hostname: string; }

const HOSTS: HostSpec[] = [
  { name: 'cnoe', hostname: 'cnoe' },
  { name: 'argocd', hostname: 'argocd' },
  { name: 'kargo', hostname: 'kargo' },
  { name: 'kargo-webhooks', hostname: 'kargo-webhooks' },
  { name: 'gitea', hostname: 'gitea' },
  { name: 'headlamp', hostname: 'headlamp' },
  { name: 'keycloak', hostname: 'keycloak' },
  { name: 'kagent', hostname: 'kagent' },
  { name: 'agentgateway', hostname: 'agentgateway' },
  // Observability UIs
  { name: 'jaeger', hostname: 'jaeger' },
  { name: 'langfuse', hostname: 'langfuse' },
];

export class IngressTailscalePublishChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    HOSTS.forEach((h) => {
      new k8s.KubeService(this, `ts-${h.name}-ingress`, {
        metadata: {
          name: `ts-${h.name}-ingress`,
          namespace: 'ingress-nginx',
          annotations: {
            'tailscale.com/expose': 'true',
            'tailscale.com/hostname': h.hostname,
            'tailscale.com/tags': 'tag:k8s',
          },
        },
        spec: {
          type: 'LoadBalancer',
          loadBalancerClass: 'tailscale',
          selector: {
            'app.kubernetes.io/name': 'ingress-nginx',
            'app.kubernetes.io/component': 'controller',
          },
          ports: [
            {
              name: 'https',
              port: 443,
              targetPort: k8s.IntOrString.fromNumber(443),
              protocol: 'TCP',
            },
          ],
        },
      });
    });
  }
}
