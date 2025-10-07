import * as fs from 'fs';
import * as path from 'path';

/**
 * Generate a kustomization.yaml file for a manifests directory
 * This ensures correct resource ordering for ArgoCD/kubectl apply
 */
export function generateKustomization(manifestsDir: string): void {
  if (!fs.existsSync(manifestsDir)) {
    throw new Error(`Manifests directory does not exist: ${manifestsDir}`);
  }

  // Get all YAML files except kustomization.yaml itself
  const files = fs.readdirSync(manifestsDir)
    .filter((f) => (f.endsWith('.yaml') || f.endsWith('.yml')) && f !== 'kustomization.yaml')
    .sort();

  if (files.length === 0) {
    console.warn(`No YAML files found in ${manifestsDir}`);
    return;
  }

  // Generate kustomization content
  const kustomization = [
    'apiVersion: kustomize.config.k8s.io/v1beta1',
    'kind: Kustomization',
    'resources:',
    ...files.map((f) => `  - ${f}`),
    ''
  ].join('\n');

  const kustomizationPath = path.join(manifestsDir, 'kustomization.yaml');
  fs.writeFileSync(kustomizationPath, kustomization);
}

/**
 * Check if a directory contains a kustomization.yaml file
 */
export function hasKustomization(manifestsDir: string): boolean {
  const kustomizationPath = path.join(manifestsDir, 'kustomization.yaml');
  return fs.existsSync(kustomizationPath);
}
