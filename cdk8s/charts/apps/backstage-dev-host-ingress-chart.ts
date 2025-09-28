import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * Host-cluster ingress that exposes the dev Backstage service synced from the vcluster.
 * Routes requests arriving at backstage-dev.cnoe.localtest.me to the vcluster-managed service.
 */
export class BackstageDevHostIngressChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    new k8s.KubeIngress(this, 'backstage-dev-host-ingress', {
      metadata: {
        name: 'backstage-dev-host-ingress',
        namespace: 'dev-vcluster',
        annotations: {
          'nginx.ingress.kubernetes.io/force-ssl-redirect': 'true',
          'nginx.ingress.kubernetes.io/backend-protocol': 'HTTP',
          'argocd.argoproj.io/sync-wave': '32',
        },
        labels: {
          'app.kubernetes.io/name': 'backstage-dev-host-ingress',
          'app.kubernetes.io/part-of': 'backstage',
          'app.kubernetes.io/component': 'ingress',
          'app.kubernetes.io/instance': 'backstage-dev',
        },
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [
          {
            host: 'backstage-dev.cnoe.localtest.me',
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'backstage-dev-x-backstage-x-vcluster-dev-helm',
                      port: { number: 7007 },
                    },
                  },
                },
              ],
            },
          },
        ],
      },
    });
  }
}
