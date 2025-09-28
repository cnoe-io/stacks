import { App, YamlOutputType } from 'cdk8s';
import * as fs from 'fs';
import * as path from 'path';
import { ArgoApplicationsChartV2 } from './charts/platform/argo-applications-chart-v2';
import { ArgoCDConfigChart } from './charts/platform/argocd-config-chart';
import { IdpBuilderChartFactory } from './lib/idpbuilder-chart-factory';
import { applicationConfigs } from './config/applications';

// Register all available charts with the factory
import { BootstrapSecretsChart } from './charts/secrets/bootstrap-secrets-chart';
import { ExternalSecretsWorkloadIdentityChart } from './charts/secrets/external-secrets-workload-identity-chart';
import { HeadlampChart } from './charts/platform/headlamp-chart';
import { HeadlampKeycloakSecretsChart } from './charts/secrets/headlamp-keycloak-secrets-chart';
import { KeycloakHeadlampClientChart } from './charts/platform/keycloak-headlamp-client-chart';
import { NamespaceChart } from './charts/platform/namespace-chart';
import { NextJsSecretsChart } from './charts/secrets/nextjs-secrets-chart';
import { PostgresChart } from './charts/apps/postgres-chart';
import { RedisChart } from './charts/apps/redis-chart';
import { KargoHelmChart } from './charts/pipelines/kargo-helm-chart';
import { KargoSecretsChart } from './charts/pipelines/kargo-secrets-chart';
import { KargoPipelinesProjectChart } from './charts/pipelines/kargo-pipelines-project-chart';
import { KargoPipelinesCredentialsChart } from './charts/pipelines/kargo-pipelines-credentials-chart';
import { KargoCACertificatesChart } from './charts/pipelines/kargo-ca-certificates-chart';
import { KargoNextjsPipelineChart } from './charts/pipelines/kargo-nextjs-pipeline-chart';
import { KargoBackstagePipelineChart } from './charts/pipelines/kargo-backstage-pipeline-chart';
import { KargoGiteaWebhookSetupChart } from './charts/pipelines/kargo-gitea-webhook-setup-chart';
import { KargoWebhookPatchChart } from './charts/pipelines/kargo-webhook-patch-chart';
import { DaggerInfraChart } from './charts/infra/dagger-infra-chart';
import { AiPlatformEngineeringAzureChart } from './charts/ai-platform-engineering-azure-chart';
import { VaultChart } from './charts/infra/vault/vault-composite-chart';
import { VclusterDevChart } from './charts/apps/vcluster-dev-chart';
import { VclusterStagingChart } from './charts/apps/vcluster-staging-chart';
import { VclusterDevIngressChart } from './charts/apps/vcluster-dev-ingress-chart';
import { VclusterStagingIngressChart } from './charts/apps/vcluster-staging-ingress-chart';
import { VclusterRegistrationRbacChart } from './charts/vcluster-registration-rbac-chart';
import { VclusterRegistrationJobChart } from './charts/vcluster-registration-job-chart';
import { VclusterRegistrationCronJobChart } from './charts/vcluster-registration-cronjob-chart';
import { NextJsParameterizedChart } from './charts/apps/nextjs-parameterized-chart';
import { BackstageParameterizedChart } from './charts/apps/backstage-parameterized-chart';
import { BackstageDevHostIngressChart } from './charts/apps/backstage-dev-host-ingress-chart';
import { BackstageEnhancedChart } from './charts/apps/backstage-enhanced-chart';
import { BackstageDevApplicationChart } from './charts/apps/backstage-dev-application-chart';
import { BackstageStagingApplicationChart } from './charts/apps/backstage-staging-application-chart';
import { BackstageSecretsChart } from './charts/secrets/backstage-secrets-chart';
import { NextJsDevApplicationChart } from './charts/apps/nextjs-dev-application-chart';
import { NextJsStagingApplicationChart } from './charts/apps/nextjs-staging-application-chart';
import { GatewayApiCrdsChart } from './charts/platform/gateway-api-crds-chart';
import { KGatewayNamespaceChart } from './charts/platform/kgateway-namespace-chart';
import { KGatewayCRDsChart } from './charts/platform/kgateway-crds-chart';
import { KGatewayHelmChart } from './charts/platform/kgateway-helm-chart';
import { KGatewayGatewayClassChart } from './charts/platform/kgateway-gatewayclass-chart';
import { KGatewayMCPServersChart } from './charts/platform/kgateway-mcp-servers-chart';
import { KGatewayMCPGatewayChart } from './charts/platform/kgateway-mcp-gateway-chart';
import { KGatewayMCPRoutesChart } from './charts/platform/kgateway-mcp-routes-chart';
import { KGatewayAIServicesChart } from './charts/platform/kgateway-ai-services-chart';
import { KGatewayAgentGatewayChart } from './charts/platform/kgateway-agentgateway-chart';

// Register all charts
IdpBuilderChartFactory.register('BootstrapSecretsChart', BootstrapSecretsChart);
IdpBuilderChartFactory.register('ExternalSecretsWorkloadIdentityChart', ExternalSecretsWorkloadIdentityChart);
IdpBuilderChartFactory.register('HeadlampChart', HeadlampChart);
IdpBuilderChartFactory.register('HeadlampKeycloakSecretsChart', HeadlampKeycloakSecretsChart);
IdpBuilderChartFactory.register('KeycloakHeadlampClientChart', KeycloakHeadlampClientChart);
IdpBuilderChartFactory.register('NamespaceChart', NamespaceChart);
IdpBuilderChartFactory.register('NextJsSecretsChart', NextJsSecretsChart);
IdpBuilderChartFactory.register('PostgresChart', PostgresChart);
IdpBuilderChartFactory.register('RedisChart', RedisChart);
IdpBuilderChartFactory.register('KargoHelmChart', KargoHelmChart);
IdpBuilderChartFactory.register('KargoSecretsChart', KargoSecretsChart);
IdpBuilderChartFactory.register('KargoPipelinesProjectChart', KargoPipelinesProjectChart);
IdpBuilderChartFactory.register('KargoPipelinesCredentialsChart', KargoPipelinesCredentialsChart);
IdpBuilderChartFactory.register('KargoCACertificatesChart', KargoCACertificatesChart);
IdpBuilderChartFactory.register('KargoNextjsPipelineChart', KargoNextjsPipelineChart);
IdpBuilderChartFactory.register('KargoBackstagePipelineChart', KargoBackstagePipelineChart);
IdpBuilderChartFactory.register('KargoGiteaWebhookSetupChart', KargoGiteaWebhookSetupChart);
IdpBuilderChartFactory.register('KargoWebhookPatchChart', KargoWebhookPatchChart);
IdpBuilderChartFactory.register('DaggerInfraChart', DaggerInfraChart);
IdpBuilderChartFactory.register('AiPlatformEngineeringAzureChart', AiPlatformEngineeringAzureChart);
IdpBuilderChartFactory.register('VaultChart', VaultChart);
IdpBuilderChartFactory.register('VclusterDevChart', VclusterDevChart);
IdpBuilderChartFactory.register('VclusterStagingChart', VclusterStagingChart);
IdpBuilderChartFactory.register('VclusterDevIngressChart', VclusterDevIngressChart);
IdpBuilderChartFactory.register('VclusterStagingIngressChart', VclusterStagingIngressChart);
IdpBuilderChartFactory.register('VclusterRegistrationRbacChart', VclusterRegistrationRbacChart);
IdpBuilderChartFactory.register('VclusterRegistrationJobChart', VclusterRegistrationJobChart);
IdpBuilderChartFactory.register('VclusterRegistrationCronJobChart', VclusterRegistrationCronJobChart);
IdpBuilderChartFactory.register('NextJsParameterizedChart', NextJsParameterizedChart);
IdpBuilderChartFactory.register('BackstageParameterizedChart', BackstageParameterizedChart);
IdpBuilderChartFactory.register('BackstageDevHostIngressChart', BackstageDevHostIngressChart);
IdpBuilderChartFactory.register('BackstageEnhancedChart', BackstageEnhancedChart);
IdpBuilderChartFactory.register('BackstageDevApplicationChart', BackstageDevApplicationChart);
IdpBuilderChartFactory.register('BackstageStagingApplicationChart', BackstageStagingApplicationChart);
IdpBuilderChartFactory.register('BackstageSecretsChart', BackstageSecretsChart);
IdpBuilderChartFactory.register('NextJsDevApplicationChart', NextJsDevApplicationChart);
IdpBuilderChartFactory.register('NextJsStagingApplicationChart', NextJsStagingApplicationChart);
IdpBuilderChartFactory.register('ArgoCDConfigChart', ArgoCDConfigChart);
IdpBuilderChartFactory.register('GatewayApiCrdsChart', GatewayApiCrdsChart);
IdpBuilderChartFactory.register('KGatewayNamespaceChart', KGatewayNamespaceChart);
IdpBuilderChartFactory.register('KGatewayCRDsChart', KGatewayCRDsChart);
IdpBuilderChartFactory.register('KGatewayHelmChart', KGatewayHelmChart);
IdpBuilderChartFactory.register('KGatewayGatewayClassChart', KGatewayGatewayClassChart);
IdpBuilderChartFactory.register('KGatewayMCPServersChart', KGatewayMCPServersChart);
IdpBuilderChartFactory.register('KGatewayMCPGatewayChart', KGatewayMCPGatewayChart);
IdpBuilderChartFactory.register('KGatewayMCPRoutesChart', KGatewayMCPRoutesChart);
IdpBuilderChartFactory.register('KGatewayAIServicesChart', KGatewayAIServicesChart);
IdpBuilderChartFactory.register('KGatewayAgentGatewayChart', KGatewayAgentGatewayChart);

const outputDir = 'dist';

/**
 * Synthesis configuration options
 */
interface SynthesisOptions {
  /**
   * Output directory for generated manifests
   */
  outputDir: string;
  
  /**
   * Whether to generate Helm charts instead of raw manifests
   */
  helmOutput?: boolean;
  
  /**
   * Environment (dev, staging, production)
   */
  environment?: string;
}

/**
 * Load environment variables from a simple KEY=VALUE file.
 * Ignores blank lines and lines starting with '#'.
 */
function loadEnvFile(filePath: string): void {
  try {
    const abs = path.resolve(filePath);
    if (!fs.existsSync(abs)) return;
    const content = fs.readFileSync(abs, 'utf-8');
    for (const line of content.split(/\r?\n/)) {
      if (!line || line.trim().startsWith('#')) continue;
      const idx = line.indexOf('=');
      if (idx <= 0) continue;
      const key = line.slice(0, idx).trim();
      const value = line.slice(idx + 1).trim();
      if (key && !(key in process.env)) {
        process.env[key] = value;
      }
    }
  } catch (e) {
    console.warn('⚠ Could not load env file:', filePath, e);
  }
}

/**
 * Create the proper IDPBuilder package structure
 */
async function createPackageStructure(appName: string, outputDir: string): Promise<void> {
  const packageDir = path.join(outputDir, appName);
  const manifestsDir = path.join(packageDir, 'manifests');
  
  // Ensure directories exist
  if (!fs.existsSync(manifestsDir)) {
    fs.mkdirSync(manifestsDir, { recursive: true });
  }
}

/**
 * Synthesize a single application
 */
async function synthesizeApplication(appConfig: any, options: SynthesisOptions): Promise<void> {
  console.log(`Synthesizing application: ${appConfig.name}`);
  
  try {
    // Create package structure
    await createPackageStructure(appConfig.name, options.outputDir);
    
    // 1. Generate manifests for the application
    const manifestApp = new App({
      yamlOutputType: YamlOutputType.FILE_PER_RESOURCE,
      outdir: path.join(options.outputDir, appConfig.name, 'manifests'),
    });
    
    // Use factory to create chart with dependencies
    await IdpBuilderChartFactory.createChart(manifestApp, appConfig);
    manifestApp.synth();

    // With FILE_PER_RESOURCE, we'll have multiple YAML files in the manifests directory
    // IDPBuilder will handle these individual resource files
    console.log(`  ✓ Generated individual resource files for ${appConfig.name}`);

    // Ensure a kustomization.yaml exists so Argo CD can apply kustomize patches when needed
    try {
      const manifestsDir = path.join(options.outputDir, appConfig.name, 'manifests');
      const files = fs.readdirSync(manifestsDir)
        .filter((f) => f.endsWith('.yaml') || f.endsWith('.yml'))
        .sort();
      const kustomizationPath = path.join(manifestsDir, 'kustomization.yaml');
      const kustomization = [
        'apiVersion: kustomize.config.k8s.io/v1beta1',
        'kind: Kustomization',
        'resources:',
        ...files.map((f) => `  - ${f}`),
        ''
      ].join('\n');
      fs.writeFileSync(kustomizationPath, kustomization);
      console.log(`  ✓ Wrote kustomization.yaml for ${appConfig.name}`);
    } catch (e) {
      console.warn(`  ⚠ Could not write kustomization.yaml for ${appConfig.name}:`, e);
    }
    
    // Copy values.yaml if it exists in the source package
    const sourceValuesPath = path.join(__dirname, '..', 'ai-platform-engineering', appConfig.name, 'values.yaml');
    const destValuesPath = path.join(options.outputDir, appConfig.name, 'values.yaml');
    if (fs.existsSync(sourceValuesPath)) {
      fs.copyFileSync(sourceValuesPath, destValuesPath);
      console.log(`  ✓ Copied values.yaml for ${appConfig.name}`);
    }
    
    // 2. Generate ArgoCD Application manifest (or ApplicationSet for special cases)
    const argoOutDir = path.join(options.outputDir, '.argo', appConfig.name);
    fs.mkdirSync(argoOutDir, { recursive: true });
    const argoApp = new App({
      yamlOutputType: YamlOutputType.FILE_PER_APP,
      outdir: argoOutDir,
    });
    
    // Check if this is a parameterized application (NextJs or Backstage)
    // These now generate individual applications, not ApplicationSets
    if (appConfig.chart?.type === 'NextJsParameterizedChart' || appConfig.chart?.type === 'BackstageParameterizedChart') {
      const envName = appConfig.chart.props?.environmentName;
      if (!envName) {
        console.error(`Missing environmentName for ${appConfig.name}`);
        return;
      }
      
      // Generate the actual manifests for this specific environment
      const ChartClass = appConfig.chart.type === 'NextJsParameterizedChart' 
        ? NextJsParameterizedChart 
        : BackstageParameterizedChart;
      
      new ChartClass(manifestApp, appConfig.name, {
        environmentName: envName,
      });
      
      // Generate the ArgoCD Application that points to these manifests
      // Map the chart type and environment to the correct Application chart
      let ApplicationChartClass;
      if (appConfig.chart.type === 'NextJsParameterizedChart') {
        ApplicationChartClass = envName === 'dev' ? NextJsDevApplicationChart : NextJsStagingApplicationChart;
      } else {
        ApplicationChartClass = envName === 'dev' ? BackstageDevApplicationChart : BackstageStagingApplicationChart;
      }
      
      new ApplicationChartClass(argoApp, `${appConfig.name}-app`, {});
      
    } else if (appConfig.chart?.type === 'VclusterDevChart' || appConfig.chart?.type === 'VclusterStagingChart') {
      // Generate vcluster Application directly without ArgoApplicationsChartV2 wrapper
      // These charts already contain the full Application definition with Helm source
      const ChartClass = appConfig.chart.type === 'VclusterDevChart' ? VclusterDevChart : VclusterStagingChart;
      new ChartClass(argoApp, appConfig.name, appConfig.chart.props || {});
    } else if (appConfig.chart?.type === 'VclusterRegistrationJobChart') {
      // Registration job needs special handling - bypass wrapper to avoid cnoe:// URLs
      // Just generate the manifests, ArgoCD app will be created separately
      // For now, use standard approach but this needs to be fixed for production
      new ArgoApplicationsChartV2(argoApp, appConfig.name, {
        applicationName: appConfig.name,
        applicationNamespace: appConfig.namespace,
        manifestPath: 'manifests',
        argoCdConfig: appConfig.argocd,
        environment: options.environment
      });
    } else if (appConfig.argocd?.sources && appConfig.argocd.sources.length > 0) {
      // Multi-source application
      new ArgoApplicationsChartV2(argoApp, appConfig.name, {
        applicationName: appConfig.name,
        applicationNamespace: appConfig.namespace,
        manifestPath: 'manifests',
        argoCdConfig: appConfig.argocd,
        environment: options.environment
      });
    } else {
      // Single source application using builder within a chart
      new ArgoApplicationsChartV2(argoApp, appConfig.name, {
        applicationName: appConfig.name,
        applicationNamespace: appConfig.namespace,
        manifestPath: 'manifests',
        argoCdConfig: appConfig.argocd,
        environment: options.environment
      });
    }
    
    argoApp.synth();
    // Move generated Application YAML to root output dir with canonical name
    const argoFiles = fs.readdirSync(argoOutDir);
    const argoAppFile = argoFiles.find(f => f === 'app.yaml' || f === 'app.k8s.yaml');
    if (argoAppFile) {
      fs.renameSync(
        path.join(argoOutDir, argoAppFile),
        path.join(options.outputDir, `${appConfig.name}.yaml`)
      );
    }
    
    console.log(`✓ Successfully synthesized: ${appConfig.name}`);
  } catch (error) {
    console.error(`✗ Failed to synthesize ${appConfig.name}:`, error);
    throw error;
  }
}

/**
 * Main synthesis function with improved structure
 */
async function main() {
  const options: SynthesisOptions = {
    outputDir,
    environment: process.env.ENVIRONMENT || 'dev',
    helmOutput: process.env.HELM_OUTPUT === 'true'
  };
  // Load environment configuration for secrets and stores
  // Prefer wi.env for dev; allow overriding via ENV_FILE
  const envFile = process.env.ENV_FILE || (options.environment === 'dev' ? '../.env-files/wi.env' : '../.env-files/production.env');
  loadEnvFile(path.join(__dirname, envFile));
  
  // Clean output directory
  if (fs.existsSync(options.outputDir)) {
    fs.rmSync(options.outputDir, { recursive: true });
  }
  fs.mkdirSync(options.outputDir, { recursive: true });
  
  // Simple concurrency pool for synthesis
  const concurrency = parseInt(process.env.SYNTH_CONCURRENCY || '4', 10);
  const queue = [...applicationConfigs];
  const workers: Promise<void>[] = [];
  async function worker() {
    while (queue.length > 0) {
      const cfg = queue.shift();
      if (!cfg) break;
      await synthesizeApplication(cfg, options);
    }
  }
  for (let i = 0; i < Math.max(1, concurrency); i++) {
    workers.push(worker());
  }
  await Promise.all(workers);
  
  console.log('\nSynthesis complete!');
  console.log(`Output directory: ${options.outputDir}/`);
  console.log('\nIDPBuilder package structure:');
  console.log('- Each application has its own directory with app.yaml and manifests/');
  console.log('- Directory structure matches cnoe:// URL requirements');
  console.log('\nYou can now run: idpbuilder create -p cdk8s/dist/');
}

// Run the main function
main().catch(error => {
  console.error('Synthesis failed:', error);
  process.exit(1);
});
