import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

interface HostSpec { name: string; hostname: string; }

const HOSTS: HostSpec[] = [
  { name: 'cnoe', hostname: 'cnoe.tail286401.ts.net' },
  { name: 'argocd', hostname: 'argocd.tail286401.ts.net' },
  { name: 'kargo', hostname: 'kargo.tail286401.ts.net' },
  { name: 'kargo-webhooks', hostname: 'kargo-webhooks.tail286401.ts.net' },
  { name: 'gitea', hostname: 'gitea.tail286401.ts.net' },
  { name: 'headlamp', hostname: 'headlamp.tail286401.ts.net' },
  { name: 'keycloak', hostname: 'keycloak.tail286401.ts.net' },
  { name: 'kagent', hostname: 'kagent.tail286401.ts.net' },
  { name: 'agentgateway', hostname: 'agentgateway.tail286401.ts.net' },
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
