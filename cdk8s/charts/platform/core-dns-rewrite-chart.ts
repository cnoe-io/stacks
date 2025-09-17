import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeConfigMap } from '../../imports/k8s';

export class CoreDnsRewriteChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    const corefile = `.:53 {
    errors
    health
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    prometheus :9153
    rewrite name exact cnoe.localtest.me ingress-nginx-controller.ingress-nginx.svc.cluster.local
    rewrite name regex (.*)\\.cnoe\\.localtest\\.me ingress-nginx-controller.ingress-nginx.svc.cluster.local
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}`;

    new KubeConfigMap(this, 'coredns', {
      metadata: {
        name: 'coredns',
        namespace: 'kube-system',
        annotations: {
          'argocd.argoproj.io/sync-options': 'Replace=true',
        },
      },
      data: {
        Corefile: corefile,
      },
    });
  }
}
