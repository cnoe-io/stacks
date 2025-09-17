# VCluster GitOps with CDK8s

This guide documents how our vclusters are provisioned and registered via pure GitOps using CDK8s, and how to add applications to one or both vclusters using CDK8s.

## Overview

- Provision and register vclusters using a single CDK8s package: `vcluster-multi-env`.
- No imperative steps are required. Argo CD and External Secrets complete the registration.
- Add application packages that target a vcluster by setting the Argo CD `Application` destination `name` to `staging-vcluster` or `production-vcluster`.

## Components

- `cdk8s/charts/apps/vcluster-multi-env-chart.ts`
  - Generates base resources in the `manifests/` package directory:
    - `Ingress` exposing the vcluster endpoint (TLS passthrough for nginx).
    - Argo CD `Application` that installs the Loft `vcluster` Helm chart.
    - `ClusterSecretStore` (external-secrets) to read the Helm-generated client certs/keys from the env namespace.
    - `ExternalSecret` in `argocd` that renders an Argo CD cluster secret from those certs.
  - Generates an Argo CD `ApplicationSet` that patches/instantiates these resources for two environments: `staging` and `production`.
  - Sync order (Argo CD `sync-wave`): Helm app (10) → ClusterSecretStore (20) → ExternalSecret (100).

- `cdk8s/config/applications.ts`
  - Includes the `vcluster-multi-env` package so synthesis emits both the base `manifests/` and the top-level ApplicationSet YAML.

## Synthesis & Deploy

1) Synthesize CDK8s packages

```
cd cdk8s
npm run synth:fast
```

2) Apply with idpbuilder

```
./idpbuilder create -p cdk8s/dist

About cnoe:// paths
- idpbuilder treats `cnoe://<relative-path>` as a path relative to the Application manifest file location.
- Our CDK8s output places per‑package manifests under `dist/<package>/manifests` and the Application manifest at `dist/<package>.yaml`.
- Therefore Applications should use `repoURL: cnoe://<package>/manifests` with `path: '.'` so idpbuilder pushes the correct directory to Gitea and rewrites the repoURL.
```

Argo CD will install vclusters and automatically register them via the ExternalSecret.

3) Merge kubeconfigs locally (optional)

```
bash ref-implementation/setup-vcluster-kubeconfigs.sh

# Then use the context
kubectl config use-context staging
```

If name resolution prefers IPv6 (::1), add to your `/etc/hosts`:

```
127.0.0.1 staging-vcluster.cnoe.localtest.me
127.0.0.1 production-vcluster.cnoe.localtest.me
```

Ensure your ingress-nginx is started with TLS passthrough enabled:
`controller.extraArgs.enable-ssl-passthrough=true`.

## Adding Applications to VClusters

There are two common patterns to deploy apps into one or both vclusters using CDK8s.

### 1) Single-Environment App (e.g., to staging only)

Create a small chart that emits an Argo CD `Application` with:
- `spec.source.repoURL: cnoe://<package>/manifests`
- `spec.destination.name: staging-vcluster`

Example chart:

```ts
// cdk8s/charts/apps/my-staging-app-chart.ts
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { Application } from '../../imports/argoproj.io';

export interface MyStagingAppProps extends ChartProps {
  appName: string;       // e.g., 'my-app'
  namespace: string;     // e.g., 'my-namespace'
}

export class MyStagingAppChart extends Chart {
  constructor(scope: Construct, id: string, props: MyStagingAppProps) {
    super(scope, id, props);

    new Application(this, 'app', {
      metadata: {
        name: `${props.appName}-staging`,
        namespace: 'argocd',
        labels: { example: 'basic' }, // required for idpbuilder local packages
        finalizers: ['resources-finalizer.argocd.argoproj.io'],
      },
      spec: {
        project: 'default',
        source: {
          repoUrl: `cnoe://${props.appName}/manifests`,
          path: '.',
          targetRevision: 'HEAD',
        },
        destination: {
          name: 'staging-vcluster',
          namespace: props.namespace,
        },
        syncPolicy: {
          automated: { prune: true, selfHeal: true },
          syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
        },
      },
    });
  }
}
```

Register the chart type in `cdk8s/main-v2.ts` via the factory, then add a new package entry in `cdk8s/config/applications.ts`:

```ts
{
  name: 'my-app',
  namespace: 'my-namespace',
  chart: { type: 'MyStagingAppChart', props: { appName: 'my-app', namespace: 'my-namespace' } },
  argocd: { labels: { example: 'basic' } }
}
```

Finally, synth + `idpbuilder create -p cdk8s/dist`.

### 2) Dual-Environment App (staging and production)

Define an Argo CD `ApplicationSet` from CDK8s to create one `Application` per environment. Use a list generator and set `spec.destination.name: {{.name}}-vcluster`.

Example chart:

```ts
// cdk8s/charts/apps/my-dual-env-app-chart.ts
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { ApplicationSet } from '../../imports/argoproj.io';

export class MyDualEnvAppChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    new ApplicationSet(this, 'appset', {
      metadata: { name: 'my-app', namespace: 'argocd' },
      spec: {
        goTemplate: true,
        generators: [ { list: { elements: [ { name: 'staging' }, { name: 'production' } ] } } ],
        template: {
          metadata: { name: 'my-app-{{.name}}' },
          spec: {
            project: 'default',
            source: {
              repoUrl: 'cnoe://my-app/manifests',
              path: '.',
              targetRevision: 'HEAD',
            },
            destination: {
              name: '{{.name}}-vcluster',
              namespace: 'my-namespace',
            },
            syncPolicy: {
              automated: { prune: true, selfHeal: true },
              syncOptions: ['CreateNamespace=true'],
            },
          },
        },
      },
    });
  }
}
```

Register the chart and add a package entry for `my-app` in `cdk8s/config/applications.ts`. Synthesize and deploy via idpbuilder.

## Per‑Vcluster Add‑ons (Templating)

We support installing common add‑ons into each vcluster (e.g., External Secrets) using a dedicated ApplicationSet.

- Chart: `cdk8s/charts/apps/vcluster-addons-chart.ts`
- Package: `vcluster-addons` in `cdk8s/config/applications.ts`
- Default add‑on: `external-secrets` Helm chart (with `installCRDs: true`) installed into namespace `external-secrets` in both `staging` and `production` vclusters.

Customize add‑ons:

```ts
{
  name: 'vcluster-addons',
  namespace: 'argocd',
  chart: {
    type: 'VclusterAddonsApplicationSetChart',
    props: {
      envs: ['staging', 'production'],
      addons: [
        {
          name: 'external-secrets',
          namespace: 'external-secrets',
          repoURL: 'https://charts.external-secrets.io',
          chart: 'external-secrets',
          version: '0.10.5',
          values: { installCRDs: true },
          syncWave: '30',
        },
        // Add more addons here
      ],
    },
  },
  argocd: { /* optional labels/syncPolicy */ },
}
```

Notes:
- Each add‑on becomes an Argo CD Application per environment (`<addon>-<env>`), with destination `name: <env>-vcluster` and `namespace: <addonNamespace>`.
- `CreateNamespace=true` ensures the namespace is created in the vcluster.
- Use `syncWave` to control ordering relative to your app packages.

## Tips

- Use `labels: { example: 'basic' }` on Application metadata for idpbuilder local package detection.
- Ensure vclusters are registered (ExternalSecrets will create the Argo CD cluster secrets automatically after the Helm vcluster apps are synced).
- For local kubeconfigs on kind/WSL2, use the merge script with `HOST_PORT_OVERRIDE=8443`.

## Troubleshooting

- Connection refused to `https://<env>-vcluster.cnoe.localtest.me:443`: ensure ingress-nginx enables SSL passthrough and add IPv4 mappings to `/etc/hosts` for the vcluster hostnames.
- Argo CD reports `there are no clusters with this name`: wait for ExternalSecret to reconcile, or check 
  `kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster`.
