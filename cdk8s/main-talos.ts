/**
 * CDK8s Entry Point for Talos Linux Cluster Bootstrap
 * Feature: 102-bootstrap-talos-argocd
 *
 * Synthesizes Kubernetes manifests for:
 * - ArgoCD root application (App-of-Apps)
 * - External Secrets Operator
 * - ClusterSecretStore for Azure Key Vault
 * - Tailscale operator and services
 *
 * Output: cdk8s/dist/talos/<app>/manifests/ + ArgoCD Application YAMLs
 */

import { App, YamlOutputType } from 'cdk8s';
import * as fs from 'fs';
import * as path from 'path';
import { ArgoApplicationsChartV2 } from './charts/platform/argo-applications-chart-v2';
import { IdpBuilderChartFactory } from './lib/idpbuilder-chart-factory';
import { talosApplications } from './config/talos-applications';
import { autoRegisterCharts } from './lib/auto-register-charts';

const outputDir = 'dist/talos';

/**
 * Synthesis configuration options
 */
interface SynthesisOptions {
  outputDir: string;
  environment: string;
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
      const value = line.slice(idx + 1).trim();
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
 * Validate required environment variables for Talos synthesis
 */
function validateEnvironment(): boolean {
  const required = [
    'AZURE_CLIENT_ID',
    'AZURE_TENANT_ID',
    'AZURE_KEYVAULT_NAME',
    'GIT_REPO_URL',
  ];

  const optional = [
    'TAILSCALE_TAILNET',
    'AZURE_STORAGE_ACCOUNT',
    'GIT_BRANCH',
  ];

  let valid = true;

  for (const varName of required) {
    if (!process.env[varName]) {
      console.error(`✗ Missing required environment variable: ${varName}`);
      valid = false;
    }
  }

  for (const varName of optional) {
    if (!process.env[varName]) {
      console.warn(`⚠ Optional environment variable not set: ${varName}`);
    }
  }

  return valid;
}

/**
 * Create the IDPBuilder package structure
 */
async function createPackageStructure(appName: string, outputDir: string): Promise<void> {
  const packageDir = path.join(outputDir, appName);
  const manifestsDir = path.join(packageDir, 'manifests');

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

    const manifestsDir = path.join(options.outputDir, appConfig.name, 'manifests');

    // Single-pass synthesis - generate manifests AND ArgoCD Application
    const app = new App({
      yamlOutputType: YamlOutputType.FILE_PER_RESOURCE,
      outdir: manifestsDir,
    });

    // Create chart with factory (handles dependency resolution)
    await IdpBuilderChartFactory.createChart(app, appConfig);

    // Generate ArgoCD Application in the same synthesis pass
    // For Talos, we use the Git repo URL directly from environment
    const gitRepoUrl = process.env.GIT_REPO_URL || '';
    const gitBranch = process.env.GIT_BRANCH || 'main';

    // Extract org/repo from URL like https://github.com/org/repo.git
    const gitMatch = gitRepoUrl.match(/github\.com\/([^\/]+)\/([^\/]+?)(?:\.git)?$/);
    const github = gitMatch ? { org: gitMatch[1], repo: gitMatch[2] } : undefined;

    new ArgoApplicationsChartV2(app, `${appConfig.name}-argocd`, {
      applicationName: appConfig.name,
      applicationNamespace: appConfig.namespace,
      manifestPath: 'manifests',
      argoCdConfig: {
        ...appConfig.argocd,
        // Override source for Talos to point to Git repo
        source: github ? {
          repoURL: `https://github.com/${github.org}/${github.repo}.git`,
          path: `cdk8s/dist/talos/${appConfig.name}/manifests`,
          targetRevision: gitBranch,
        } : undefined,
      },
      environment: options.environment,
      github,
    });

    // Synthesize all charts
    app.synth();

    console.log(`  ✓ Generated resources for ${appConfig.name}`);

    // Generate kustomization.yaml (excluding ArgoCD Application file)
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

    // Move ArgoCD Application to package root (for idpbuilder compatibility)
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
 * Main synthesis function for Talos cluster
 */
async function main() {
  const startTime = Date.now();

  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  CDK8s Synthesis for Talos Linux Cluster');
  console.log('  Feature: 102-bootstrap-talos-argocd');
  console.log('═══════════════════════════════════════════════════════════════\n');

  const options: SynthesisOptions = {
    outputDir,
    environment: process.env.ENVIRONMENT || 'talos',
  };

  // Load environment configuration
  const envFile = process.env.ENV_FILE || '../scripts/.env';
  loadEnvFile(path.join(__dirname, envFile));

  // Validate required environment
  if (!validateEnvironment()) {
    console.error('\n✗ Environment validation failed');
    console.log('Create scripts/.env with required variables (see scripts/.env.template)');
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

  // Filter applications if specific app requested
  const targetApp = process.argv[2];
  let applications = talosApplications;

  if (targetApp) {
    applications = talosApplications.filter((a) => a.name === targetApp);
    if (applications.length === 0) {
      console.error(`✗ Application not found: ${targetApp}`);
      console.log('Available applications:', talosApplications.map((a) => a.name).join(', '));
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
  console.log(`   Applications: ${applications.length}`);
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
  console.log(`   - Applications: ${applications.length}`);
  console.log(`   - Duration: ${(duration / 1000).toFixed(2)}s`);
  console.log(`   - Output: ${options.outputDir}/`);
  console.log('\n📦 Package structure:');
  console.log('   - Each app has: <app-name>.yaml + <app-name>/manifests/');
  console.log('\n🚀 Next steps:');
  console.log('   1. Commit manifests to Git');
  console.log('   2. Run: ./scripts/bootstrap-cluster.sh');
  console.log('   3. ArgoCD will sync from: ' + (process.env.GIT_REPO_URL || '<GIT_REPO_URL>'));
}

// Run the main function
main().catch((error) => {
  console.error('❌ Synthesis failed:', error);
  process.exit(1);
});
