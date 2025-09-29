import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { Application, ApplicationSpec } from '../../imports/argoproj.io';

/**
 * Creates ArgoCD Application for Backstage Dev environment
 * Points to pre-generated manifests in Gitea repository
 */
export class BackstageDevApplicationChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    new Application(this, 'backstage-dev', {
      metadata: {
        name: 'backstage-dev',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
          'kargo.akuity.io/authorized-stage': 'kargo-pipelines:backstage-dev'
        },
        labels: {
          'app.kubernetes.io/name': 'backstage',
          'app.kubernetes.io/instance': 'backstage-dev',
          'app.kubernetes.io/component': 'developer-portal',
          'app.kubernetes.io/part-of': 'platform',
          'app.kubernetes.io/managed-by': 'cdk8s',
          'environment': 'dev'
        },
        finalizers: ['resources-finalizer.argocd.argoproj.io']
      },
      spec: {
        project: 'default',
        destination: {
          name: 'dev-vcluster',  // Deploy to vcluster like nextjs-dev
          namespace: 'backstage'
        },
        source: {
          repoUrl: 'cnoe://backstage-dev/manifests',
          targetRevision: 'HEAD',
          path: '.'
        },
        syncPolicy: {
          automated: {
            prune: true,
            selfHeal: true
          },
          syncOptions: [
            'CreateNamespace=true',
            'ServerSideApply=true',
            'SkipDryRunOnMissingResource=true'
          ],
          retry: {
            limit: 5,
            backoff: {
              duration: '10s',
              factor: 2,
              maxDuration: '5m'
            }
          }
        },
        ignoreDifferences: [
          {
            group: 'apps',
            kind: 'Deployment',
            jsonPointers: [
              '/spec/replicas',
              '/spec/template/metadata/annotations'
            ]
          },
          {
            group: 'apps',
            kind: 'StatefulSet',
            jsonPointers: [
              '/spec/replicas',
              '/spec/volumeClaimTemplates'
            ]
          },
          {
            kind: 'Service',
            jsonPointers: ['/spec/clusterIP']
          },
          {
            group: 'networking.k8s.io',
            kind: 'Ingress',
            jsonPointers: ['*']
          }
        ]
      } as ApplicationSpec
    });
  }
}