/**
 * Unified CDK8s Entry Point
 * Feature: 106-consolidate-bootstrap-between
 *
 * Synthesizes Kubernetes manifests for both KIND and Talos clusters.
 * Uses CLUSTER_TYPE environment variable to determine:
 * - Which applications to include (filtered by clusterType field)
 * - How ArgoCD Application sources are generated (cnoe:// vs GitHub)
 *
 * Constitution Alignment:
 * - Principle I (Type-Safe IaC): Single entry point
 * - Principle II (GitOps-First): Cluster-type-driven ArgoCD sources
 * - Principle IX (Unified Bootstrap): CLUSTER_TYPE environment variable
 *
 * Output: cdk8s/dist/<app>/manifests/ + ArgoCD Application YAMLs
 */

import { App, YamlOutputType } from 'cdk8s';
import * as fs from 'fs';
import * as path from 'path';
import { ArgoApplicationsChartV2 } from './charts/platform/argo-applications-chart-v2';
import { IdpBuilderChartFactory } from './lib/idpbuilder-chart-factory';
import { applicationConfigs } from './config/applications';
import { autoRegisterCharts } from './lib/auto-register-charts';
import {
  getClusterType,
  getSourceUrl,
  shouldIncludeApp,
  validateEnvironmentForCluster,
  ClusterType,
} from './lib/source-url';

/**
 * Synthesis configuration options
 */
interface SynthesisOptions {
  outputDir: string;
  environment: string;
  clusterType: ClusterType;
}

/**
 * Load environment variables from a simple KEY=VALUE file.
 */
function loadEnvFile(filePath: string): void {
  try {
    const abs = path.resolve(filePath);
    if (!fs.existsSync(abs)) {
      console.warn(`⚠ Environment file not found: ${filePath}`);
      return;
    }
    const content = fs.readFileSync(abs, 'utf-8');
    for (const line of content.split(/\r?\n/)) {
      if (!line || line.trim().startsWith('#')) continue;
      const idx = line.indexOf('=');
      if (idx <= 0) continue;
      const key = line.slice(0, idx).trim();
      let value = line.slice(idx + 1).trim();
      // Strip surrounding quotes (single or double)
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      if (key && !(key in process.env)) {
        process.env[key] = value;
      }
    }
    console.log(`✓ Loaded environment from: ${filePath}`);
  } catch (e) {
    console.warn('⚠ Could not load env file:', filePath, e);
  }
}

/**
 * Create the IDPBuilder package structure
 */
async function createPackageStructure(
  appName: string,
  outputDir: string
): Promise<void> {
  const packageDir = path.join(outputDir, appName);
  const manifestsDir = path.join(packageDir, 'manifests');

  if (!fs.existsSync(manifestsDir)) {
    fs.mkdirSync(manifestsDir, { recursive: true });
  }
}

/**
 * Synthesize a single application using optimized single-pass synthesis
 */
async function synthesizeApplication(
  appConfig: any,
  options: SynthesisOptions
): Promise<void> {
  console.log(`Synthesizing application: ${appConfig.name}`);

  try {
    // Create package structure
    await createPackageStructure(appConfig.name, options.outputDir);

    const manifestsDir = path.join(options.outputDir, appConfig.name, 'manifests');

    // Single-pass synthesis - generate both manifests AND ArgoCD Application
    const app = new App({
      yamlOutputType: YamlOutputType.FILE_PER_RESOURCE,
      outdir: manifestsDir,
    });

    // Standard charts: use factory to create chart with dependencies
    await IdpBuilderChartFactory.createChart(app, appConfig);

    // Get source URL based on cluster type
    const source = getSourceUrl(appConfig.name, options.clusterType);

    // Build ArgoCD config with appropriate source
    const argoCdConfig = {
      ...appConfig.argocd,
    };

    // For Talos, use multi-source mode with GitHub URLs
    if (options.clusterType === 'talos' && source.path) {
      argoCdConfig.sources = [
        {
          repoURL: source.repoURL,
          path: source.path,
          targetRevision: source.targetRevision || 'main',
        },
      ];
    }

    // Generate ArgoCD Application in the same synthesis pass
    new ArgoApplicationsChartV2(app, `${appConfig.name}-argocd`, {
      applicationName: appConfig.name,
      applicationNamespace: appConfig.namespace,
      manifestPath: 'manifests',
      argoCdConfig,
      environment: options.environment,
    });

    // Single synth call generates everything
    app.synth();

    console.log(`  ✓ Generated resources for ${appConfig.name}`);

    // Generate kustomization.yaml (excluding the ArgoCD Application file)
    try {
      const allFiles = fs.readdirSync(manifestsDir);
      const resourceFiles = allFiles
        .filter(
          (f) =>
            (f.endsWith('.yaml') || f.endsWith('.yml')) &&
            !f.includes('Application') &&
            f !== 'kustomization.yaml'
        )
        .sort();

      if (resourceFiles.length > 0) {
        const kustomization = [
          'apiVersion: kustomize.config.k8s.io/v1beta1',
          'kind: Kustomization',
          'resources:',
          ...resourceFiles.map((f) => `  - ${f}`),
          '',
        ].join('\n');
        fs.writeFileSync(path.join(manifestsDir, 'kustomization.yaml'), kustomization);
        console.log(`  ✓ Generated kustomization.yaml`);
      }
    } catch (e) {
      console.warn(`  ⚠ Could not write kustomization.yaml for ${appConfig.name}:`, e);
    }

    // Move ArgoCD Application to package root (IdpBuilder requirement)
    try {
      const argoAppFiles = fs
        .readdirSync(manifestsDir)
        .filter((f) => f.includes('Application') && f.endsWith('.yaml'));

      if (argoAppFiles.length > 0) {
        const argoAppFile = argoAppFiles[0];
        fs.renameSync(
          path.join(manifestsDir, argoAppFile),
          path.join(options.outputDir, `${appConfig.name}.yaml`)
        );
        console.log(`  ✓ Moved ArgoCD Application to package root`);
      }
    } catch (e) {
      console.warn(`  ⚠ Could not move ArgoCD Application for ${appConfig.name}:`, e);
    }

    console.log(`✓ Successfully synthesized: ${appConfig.name}`);
  } catch (error) {
    console.error(`✗ Failed to synthesize ${appConfig.name}:`, error);
    throw error;
  }
}

/**
 * Main synthesis function with unified cluster support
 */
async function main() {
  const startTime = Date.now();

  // Get cluster type from environment (defaults to 'kind')
  const clusterType = getClusterType();

  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Unified CDK8s Synthesis`);
  console.log(`  Cluster Type: ${clusterType.toUpperCase()}`);
  console.log(`  Feature: 106-consolidate-bootstrap-between`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  const options: SynthesisOptions = {
    outputDir: 'dist',
    environment: process.env.ENVIRONMENT || (clusterType === 'kind' ? 'dev' : 'talos'),
    clusterType,
  };

  // Load environment configuration based on cluster type
  const envFile =
    process.env.ENV_FILE ||
    (clusterType === 'kind' ? '../.env-files/kind.env' : '../.env-files/talos.env');
  loadEnvFile(path.join(__dirname, envFile));

  // Validate environment for cluster type (Talos has stricter requirements)
  try {
    validateEnvironmentForCluster(clusterType);
  } catch (error) {
    console.error(`\n✗ Environment validation failed for ${clusterType}:`);
    console.error((error as Error).message);
    if (clusterType === 'talos') {
      console.log('\nCreate .env-files/talos.env with required variables');
      console.log('See scripts/.env.template for reference');
    }
    process.exit(1);
  }

  // Auto-register all charts from charts/ directory
  console.log('🔧 Auto-registering charts...');
  autoRegisterCharts();
  console.log(`  Registered: ${IdpBuilderChartFactory.getRegisteredTypes().length} chart types`);

  // Clean output directory
  if (fs.existsSync(options.outputDir)) {
    fs.rmSync(options.outputDir, { recursive: true });
  }
  fs.mkdirSync(options.outputDir, { recursive: true });

  // Filter applications by cluster type
  const filteredApps = applicationConfigs.filter((app) =>
    shouldIncludeApp(app.clusterType, clusterType)
  );

  // Check for specific app requested via CLI
  const targetApp = process.argv[2];
  let applications = filteredApps;

  if (targetApp) {
    applications = filteredApps.filter((a) => a.name === targetApp);
    if (applications.length === 0) {
      console.error(`✗ Application not found: ${targetApp}`);
      console.log(
        'Available applications for',
        clusterType + ':',
        filteredApps.map((a) => a.name).join(', ')
      );
      process.exit(1);
    }
  }

  // Concurrent synthesis with worker pool
  const concurrency = parseInt(process.env.SYNTH_CONCURRENCY || '4', 10);
  const queue = [...applications];
  const workers: Promise<void>[] = [];

  async function worker() {
    while (queue.length > 0) {
      const cfg = queue.shift();
      if (!cfg) break;
      await synthesizeApplication(cfg, options);
    }
  }

  console.log(`\n🚀 Starting synthesis with ${concurrency} workers...`);
  console.log(`   Cluster Type: ${clusterType}`);
  console.log(`   Applications: ${applications.length} (filtered from ${applicationConfigs.length})`);
  console.log(`   Output: ${options.outputDir}/\n`);

  for (let i = 0; i < Math.max(1, concurrency); i++) {
    workers.push(worker());
  }
  await Promise.all(workers);

  const duration = Date.now() - startTime;

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('✅ Synthesis complete!');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`📊 Stats:`);
  console.log(`   - Cluster Type: ${clusterType}`);
  console.log(`   - Applications: ${applications.length}`);
  console.log(`   - Duration: ${(duration / 1000).toFixed(2)}s`);
  console.log(`   - Output: ${options.outputDir}/`);
  console.log('\n📦 Package structure:');
  console.log('   - Each app has: <app-name>.yaml + <app-name>/manifests/');
  console.log('\n🚀 Next steps:');

  if (clusterType === 'kind') {
    console.log('   1. Run: idpbuilder create --package cdk8s/dist/');
    console.log('   2. Or use: source deployment/scripts/cluster-menu.sh && cluster-deploy');
  } else {
    console.log('   1. Commit manifests to Git');
    console.log('   2. Run: ./scripts/bootstrap-cluster.sh');
    console.log(
      '   3. ArgoCD will sync from: ' + (process.env.GIT_REPO_URL || '<GIT_REPO_URL>')
    );
  }
}

// Run the main function
main().catch((error) => {
  console.error('❌ Synthesis failed:', error);
  process.exit(1);
});
