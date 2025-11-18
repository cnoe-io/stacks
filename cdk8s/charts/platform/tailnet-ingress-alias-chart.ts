import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

interface AliasRule {
  namespace: string;
  name: string;
  host: string;
  paths: { path: string; service: string; port: number | string; pathType?: string; }[];
}

const ALIASES: AliasRule[] = [
  {
    namespace: 'argocd',
    name: 'argocd-tailnet-alias',
    host: 'argocd.tail286401.ts.net',
    paths: [{ path: '/', service: 'argocd-server', port: 443, pathType: 'Prefix' }],
  },
  {
    namespace: 'backstage',
    name: 'cnoe-tailnet-alias',
    host: 'cnoe.tail286401.ts.net',
    paths: [{ path: '/', service: 'backstage', port: 7007, pathType: 'Prefix' }],
  },
  {
    namespace: 'kargo',
    name: 'kargo-tailnet-alias',
    host: 'kargo.tail286401.ts.net',
    paths: [
      { path: '/', service: 'kargo-api', port: 80, pathType: 'ImplementationSpecific' },
      { path: '/webhooks', service: 'kargo-external-webhooks-server', port: 80, pathType: 'ImplementationSpecific' },
    ],
  },
  {
    namespace: 'kargo',
    name: 'kargo-webhooks-tailnet-alias',
    host: 'kargo-webhooks.tail286401.ts.net',
    paths: [{ path: '/', service: 'kargo-external-webhooks-server', port: 80, pathType: 'Prefix' }],
  },
  {
    namespace: 'gitea',
    name: 'gitea-tailnet-alias',
    host: 'gitea.tail286401.ts.net',
    paths: [{ path: '/', service: 'my-gitea-http', port: 3000, pathType: 'Prefix' }],
  },
  {
    namespace: 'headlamp',
    name: 'headlamp-tailnet-alias',
    host: 'headlamp.tail286401.ts.net',
    paths: [{ path: '/', service: 'headlamp', port: 80, pathType: 'Prefix' }],
  },
  {
    namespace: 'keycloak',
    name: 'keycloak-tailnet-alias',
    host: 'keycloak.tail286401.ts.net',
    paths: [{ path: '/keycloak', service: 'keycloak', port: 'http', pathType: 'ImplementationSpecific' }],
  },
  {
    namespace: 'kagent',
    name: 'kagent-tailnet-alias',
    host: 'kagent.tail286401.ts.net',
    paths: [{ path: '/', service: 'kagent-ui', port: 8080, pathType: 'Prefix' }],
  },
  {
    namespace: 'kgateway-system',
    name: 'agentgateway-tailnet-alias',
    host: 'agentgateway.tail286401.ts.net',
    paths: [{ path: '/', service: 'kgateway', port: 9977, pathType: 'Prefix' }],
  },
];

export class TailnetIngressAliasChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    ALIASES.forEach((rule) => {
      new k8s.KubeIngress(this, rule.name, {
        metadata: {
          name: rule.name,
          namespace: rule.namespace,
          annotations: {
            'kubernetes.io/ingress.class': 'nginx',
          },
        },
        spec: {
          ingressClassName: 'nginx',
          rules: [
            {
              host: rule.host,
              http: {
                paths: rule.paths.map((p) => ({
                  path: p.path,
                  pathType: <k8s.HttpIngressPath['pathType']>(p.pathType || 'Prefix'),
                  backend: {
                    service: {
                      name: p.service,
                      port: typeof p.port === 'number'
                        ? { number: p.port }
                        : { name: p.port },
                    },
                  },
                })),
              },
            },
          ],
        },
      });
    });
  }
}
