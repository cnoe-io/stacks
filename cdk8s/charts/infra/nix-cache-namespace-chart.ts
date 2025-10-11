import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface NixCacheNamespaceChartProps extends ChartProps {
  namespaceName?: string;
}

export class NixCacheNamespaceChart extends Chart {
  constructor(scope: Construct, id: string, props?: NixCacheNamespaceChartProps) {
    super(scope, id, props);

    const namespaceName = props?.namespaceName || 'nix-cache';

    // Create nix-cache namespace with sync wave annotation
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespaceName,
        labels: {
          'app.kubernetes.io/name': 'nix-cache',
          'app.kubernetes.io/component': 'infrastructure',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-110',
        },
      },
    });
  }
}
