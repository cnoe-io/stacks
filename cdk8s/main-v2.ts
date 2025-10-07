import { App, YamlOutputType } from 'cdk8s';
import * as fs from 'fs';
import * as path from 'path';
import { ArgoApplicationsChartV2 } from './charts/platform/argo-applications-chart-v2';
import { IdpBuilderChartFactory } from './lib/idpbuilder-chart-factory';
import { applicationConfigs } from './config/applications';
import { autoRegisterCharts } from './lib/auto-register-charts';
import { generateKustomization } from './lib/kustomization-generator';

const outputDir = 'dist';

/**
 * Synthesis configuration options
 */
interface SynthesisOptions {
  outputDir: string;
  environment?: string;
}

/**
 * Load environment variables from a simple KEY=VALUE file.
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
 * Synthesize a single application using optimized single-pass synthesis
 */
async function synthesizeApplication(appConfig: any, options: SynthesisOptions): Promise<void> {
  console.log(`Synthesizing application: ${appConfig.name}`);

  try {
    // Create package structure
    await createPackageStructure(appConfig.name, options.outputDir);

    const manifestsDir = path.join(options.outputDir, appConfig.name, 'manifests');

    // OPTIMIZATION 1: Single-pass synthesis - generate both manifests AND ArgoCD Application
    const app = new App({
      yamlOutputType: YamlOutputType.FILE_PER_RESOURCE,
      outdir: manifestsDir,
    });

    // Standard charts: use factory to create chart with dependencies
    await IdpBuilderChartFactory.createChart(app, appConfig);

    // Generate ArgoCD Application in the same synthesis pass
    new ArgoApplicationsChartV2(app, `${appConfig.name}-argocd`, {
      applicationName: appConfig.name,
      applicationNamespace: appConfig.namespace,
      manifestPath: 'manifests',
      argoCdConfig: appConfig.argocd,
      environment: options.environment
    });

    // Single synth call generates everything
    app.synth();

    console.log(`  ✓ Generated resources for ${appConfig.name}`);

    // OPTIMIZATION 3: Use extracted kustomization generator
    try {
      // Generate kustomization.yaml (excluding the ArgoCD Application file)
      const allFiles = fs.readdirSync(manifestsDir);
      const resourceFiles = allFiles
        .filter((f) => (f.endsWith('.yaml') || f.endsWith('.yml'))
          && !f.includes('Application')
          && f !== 'kustomization.yaml')
        .sort();

      if (resourceFiles.length > 0) {
        const kustomization = [
          'apiVersion: kustomize.config.k8s.io/v1beta1',
          'kind: Kustomization',
          'resources:',
          ...resourceFiles.map((f) => `  - ${f}`),
          ''
        ].join('\n');
        fs.writeFileSync(path.join(manifestsDir, 'kustomization.yaml'), kustomization);
        console.log(`  ✓ Generated kustomization.yaml`);
      }
    } catch (e) {
      console.warn(`  ⚠ Could not write kustomization.yaml for ${appConfig.name}:`, e);
    }

    // Move ArgoCD Application to package root (IdpBuilder requirement)
    try {
      const argoAppFiles = fs.readdirSync(manifestsDir)
        .filter(f => f.includes('Application') && f.endsWith('.yaml'));

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
 * Main synthesis function with optimizations
 */
async function main() {
  const startTime = Date.now();

  const options: SynthesisOptions = {
    outputDir,
    environment: process.env.ENVIRONMENT || 'dev',
  };

  // Load environment configuration
  const envFile = process.env.ENV_FILE || (options.environment === 'dev' ? '../.env-files/wi.env' : '../.env-files/production.env');
  loadEnvFile(path.join(__dirname, envFile));

  // OPTIMIZATION 2: Auto-register all charts
  console.log('🔧 Auto-registering charts...');
  autoRegisterCharts();

  // Clean output directory
  if (fs.existsSync(options.outputDir)) {
    fs.rmSync(options.outputDir, { recursive: true });
  }
  fs.mkdirSync(options.outputDir, { recursive: true });

  // Concurrent synthesis with worker pool
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

  console.log(`\n🚀 Starting synthesis with ${concurrency} workers...`);
  for (let i = 0; i < Math.max(1, concurrency); i++) {
    workers.push(worker());
  }
  await Promise.all(workers);

  const duration = Date.now() - startTime;

  console.log('\n✅ Synthesis complete!');
  console.log(`📊 Stats:`);
  console.log(`   - Applications: ${applicationConfigs.length}`);
  console.log(`   - Duration: ${(duration / 1000).toFixed(2)}s`);
  console.log(`   - Output: ${options.outputDir}/`);
  console.log('\n📦 IDPBuilder package structure:');
  console.log('   - Each app has: <app-name>.yaml + <app-name>/manifests/');
  console.log('   - Ready for: idpbuilder create -p cdk8s/dist/');
}

// Run the main function
main().catch(error => {
  console.error('❌ Synthesis failed:', error);
  process.exit(1);
});
