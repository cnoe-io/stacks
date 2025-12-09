import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { 
  Application, 
  ApplicationSpec,
  ApplicationSpecSource,
  ApplicationSpecSources,
  ApplicationSpecDestination,
  ApplicationSpecSyncPolicy,
  ApplicationSpecIgnoreDifferences
} from '../../imports/argoproj.io';
import { ApplicationConfig } from '../../lib/idpbuilder-types';

export interface ArgoApplicationsChartV2Props extends ChartProps {
  /**
   * Application name
   */
  applicationName: string;

  /**
   * Application namespace
   */
  applicationNamespace: string;

  /**
   * Path to manifests (relative to package directory)
   * @default 'manifests'
   */
  manifestPath?: string;

  /**
   * ArgoCD configuration from ApplicationConfig
   */
  argoCdConfig?: ApplicationConfig['argocd'] & {
    /**
     * Directory exclude pattern for ArgoCD directory source.
     * Used to exclude certain files from sync (e.g., 'catalog-info.yaml').
     */
    directoryExclude?: string;
  };

  /**
   * Environment (dev, staging, production)
   * @default 'dev'
   */
  environment?: string;

  /**
   * GitHub configuration for production environments
   */
  github?: {
    org: string;
    repo: string;
  };
}

/**
 * Enhanced ArgoCD Applications Chart with type safety and better structure
 */
export class ArgoApplicationsChartV2 extends Chart {
  private readonly application: Application;

  constructor(scope: Construct, id: string, props: ArgoApplicationsChartV2Props) {
    super(scope, id, props);

    const environment = props.environment || process.env.ENVIRONMENT || 'dev';
    const isLocal = environment === 'dev';
    const manifestPath = props.manifestPath || 'manifests';

    // Build metadata
    const metadata = this.buildMetadata(props);

    // Build spec based on configuration
    const spec = props.argoCdConfig?.sources && props.argoCdConfig.sources.length > 0
      ? this.buildMultiSourceSpec(props)
      : this.buildSingleSourceSpec(props, isLocal, manifestPath);

    // Create the Application
    this.application = new Application(this, 'application', {
      metadata,
      spec
    });
  }

  /**
   * Get the generated Application resource
   */
  public getApplication(): Application {
    return this.application;
  }

  /**
   * Build metadata for the Application
   */
  private buildMetadata(props: ArgoApplicationsChartV2Props): any {
    const labels: Record<string, string> = {
      'app.kubernetes.io/managed-by': 'cdk8s',
      'app.kubernetes.io/environment': props.environment || 'dev',
      'app.kubernetes.io/part-of': 'platform',
      'app.kubernetes.io/name': props.applicationName,
      'example': 'basic', // Required for idpbuilder
      ...props.argoCdConfig?.labels
    };

    const metadata: any = {
      name: props.applicationName,
      namespace: 'argocd',
      labels,
      finalizers: ['resources-finalizer.argocd.argoproj.io']
    };

    // Merge custom annotations and ensure sync-wave is preserved
    const annotations: Record<string, string> = {
      ...(props.argoCdConfig?.annotations || {})
    };
    if (props.argoCdConfig?.syncWave) {
      annotations['argocd.argoproj.io/sync-wave'] = props.argoCdConfig.syncWave;
    }
    // Ensure Kargo can mutate the Backstage app for argocd-update
    if (props.applicationName === 'backstage' && !annotations['kargo.akuity.io/authorized-stage']) {
      annotations['kargo.akuity.io/authorized-stage'] = 'kargo-pipelines:backstage-dev';
    }
    if (Object.keys(annotations).length > 0) {
      metadata.annotations = annotations;
    }

    return metadata;
  }

  /**
   * Build single source Application spec
   */
  private buildSingleSourceSpec(
    props: ArgoApplicationsChartV2Props,
    isLocal: boolean,
    manifestPath: string
  ): ApplicationSpec {
    let source: any;

    if (isLocal) {
      // Local development using cnoe://
      source = {
        repoUrl: `cnoe://${props.applicationName}/${manifestPath}`,
        path: '.',
        targetRevision: 'HEAD'
      };
    } else {
      // Production using GitHub
      if (!props.github) {
        throw new Error('GitHub configuration required for non-local environments');
      }
      source = {
        repoUrl: `https://github.com/${props.github.org}/${props.github.repo}.git`,
        path: `packages/${props.applicationName}/${manifestPath}`,
        targetRevision: 'HEAD'
      };
    }

    // Add directory exclude pattern if specified
    if (props.argoCdConfig?.directoryExclude) {
      source.directory = {
        exclude: props.argoCdConfig.directoryExclude
      };
    }

    return this.buildBaseSpec(props, { source: source as ApplicationSpecSource });
  }

  /**
   * Build multi-source Application spec
   */
  private buildMultiSourceSpec(props: ArgoApplicationsChartV2Props): ApplicationSpec {
    if (!props.argoCdConfig?.sources) {
      throw new Error('Sources configuration required for multi-source application');
    }

    const sources: ApplicationSpecSources[] = props.argoCdConfig.sources.map(src => this.mapSource(src));

    return this.buildBaseSpec(props, { sources });
  }

  /**
   * Map configuration source to typed ApplicationSpecSources
   */
  private mapSource(source: any): ApplicationSpecSources {
    const mappedSource: any = {
      repoUrl: source.repoURL
    };

    // Add optional fields if present
    if (source.path) mappedSource.path = source.path;
    if (source.targetRevision) mappedSource.targetRevision = source.targetRevision;
    if (source.chart) mappedSource.chart = source.chart;
    if (source.ref) mappedSource.ref = source.ref;

    // Map Helm configuration
    if (source.helm) {
      mappedSource.helm = {};
      if (source.helm.valueFiles) {
        mappedSource.helm.valueFiles = source.helm.valueFiles;
      }
      if (source.helm.values) {
        mappedSource.helm.values = source.helm.values;
      }
      if (source.helm.parameters) {
        mappedSource.helm.parameters = source.helm.parameters.map((p: any) => ({
          name: p.name,
          value: p.value
        }));
      }
    }

    return mappedSource as ApplicationSpecSources;
  }

  /**
   * Build base Application spec with common properties
   */
  private buildBaseSpec(
    props: ArgoApplicationsChartV2Props,
    sourceConfig: { source?: ApplicationSpecSource; sources?: ApplicationSpecSources[] }
  ): ApplicationSpec {
    // Choose destination by cluster name if environment label requests a vcluster
    const envLabel = props.argoCdConfig?.labels?.['app.kubernetes.io/environment'];
    const destination: ApplicationSpecDestination =
      envLabel === 'dev' || envLabel === 'staging'
        ? {
            name: `${envLabel}-vcluster`,
            namespace: props.applicationNamespace,
          }
        : {
            server: 'https://kubernetes.default.svc',
            namespace: props.applicationNamespace,
          };

    const syncPolicy: ApplicationSpecSyncPolicy = props.argoCdConfig?.syncPolicy || {
      automated: {
        selfHeal: true,
        prune: true
      },
      syncOptions: ['CreateNamespace=true']
    };

    const spec: any = {
      project: 'default',
      destination,
      syncPolicy,
      ...sourceConfig
    };

    // Add ignore differences if specified
    if (props.argoCdConfig?.ignoreDifferences) {
      spec.ignoreDifferences = props.argoCdConfig.ignoreDifferences;
    }

    return spec as ApplicationSpec;
  }
}

/**
 * Builder class for creating ArgoCD Applications with fluent API
 */
export class ApplicationBuilder {
  private name?: string;
  private namespace?: string;
  private sources: ApplicationSpecSources[] = [];
  private syncPolicy?: ApplicationSpecSyncPolicy;
  private labels: Record<string, string> = {};
  private annotations: Record<string, string> = {};
  private ignoreDifferences?: ApplicationSpecIgnoreDifferences[];

  withName(name: string): this {
    this.name = name;
    return this;
  }

  withNamespace(namespace: string): this {
    this.namespace = namespace;
    return this;
  }

  withLabel(key: string, value: string): this {
    this.labels[key] = value;
    return this;
  }

  withAnnotation(key: string, value: string): this {
    this.annotations[key] = value;
    return this;
  }

  withSyncWave(wave: string): this {
    return this.withAnnotation('argocd.argoproj.io/sync-wave', wave);
  }

  withHelmSource(config: {
    repoURL: string;
    chart: string;
    version: string;
    values?: any;
    valueFiles?: string[];
  }): this {
    const source: any = {
      repoUrl: config.repoURL,
      chart: config.chart,
      targetRevision: config.version
    };

    if (config.values || config.valueFiles) {
      source.helm = {};
      if (config.values) {
        source.helm.values = typeof config.values === 'string' 
          ? config.values 
          : JSON.stringify(config.values, null, 2);
      }
      if (config.valueFiles) {
        source.helm.valueFiles = config.valueFiles;
      }
    }

    this.sources.push(source as ApplicationSpecSources);
    return this;
  }

  withGitSource(config: {
    repoURL: string;
    path: string;
    targetRevision?: string;
    ref?: string;
  }): this {
    const source: any = {
      repoUrl: config.repoURL,
      path: config.path,
      targetRevision: config.targetRevision || 'HEAD'
    };

    if (config.ref) {
      source.ref = config.ref;
    }

    this.sources.push(source as ApplicationSpecSources);
    return this;
  }

  withLocalSource(packageName: string, manifestPath: string = 'manifests'): this {
    return this.withGitSource({
      repoURL: `cnoe://${packageName}/${manifestPath}`,
      path: '.',
      targetRevision: 'HEAD'
    });
  }

  withSyncPolicy(policy: ApplicationSpecSyncPolicy): this {
    this.syncPolicy = policy;
    return this;
  }

  withAutomatedSync(prune: boolean = true, selfHeal: boolean = true): this {
    this.syncPolicy = {
      automated: { prune, selfHeal },
      syncOptions: ['CreateNamespace=true']
    };
    return this;
  }

  withIgnoreDifferences(differences: ApplicationSpecIgnoreDifferences[]): this {
    this.ignoreDifferences = differences;
    return this;
  }

  build(scope: Construct, id: string): Application {
    if (!this.name || !this.namespace) {
      throw new Error('Application name and namespace are required');
    }

    if (this.sources.length === 0) {
      throw new Error('At least one source must be specified');
    }

    // Set default labels
    const defaultLabels = {
      'app.kubernetes.io/managed-by': 'cdk8s',
      'app.kubernetes.io/name': this.name,
      'example': 'basic'
    };

    const metadata: any = {
      name: this.name,
      namespace: 'argocd',
      labels: { ...defaultLabels, ...this.labels },
      finalizers: ['resources-finalizer.argocd.argoproj.io']
    };

    if (Object.keys(this.annotations).length > 0) {
      metadata.annotations = this.annotations;
    }

    const spec: any = {
      project: 'default',
      destination: {
        server: 'https://kubernetes.default.svc',
        namespace: this.namespace
      },
      syncPolicy: this.syncPolicy || {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true']
      }
    };

    // Use single source or multi-source based on count
    if (this.sources.length === 1) {
      spec.source = this.sources[0];
    } else {
      spec.sources = this.sources;
    }

    if (this.ignoreDifferences) {
      spec.ignoreDifferences = this.ignoreDifferences;
    }

    return new Application(scope, id, { metadata, spec: spec as ApplicationSpec });
  }
}
