/**
 * ArgoCDHelmChart - Deploys ArgoCD via Helm for Talos cluster bootstrap
 * Feature: 102-bootstrap-talos-argocd
 *
 * This chart deploys ArgoCD using the official Helm chart which:
 * - Installs ArgoCD server, repo-server, and controller
 * - Configures high availability with Redis
 * - Sets up RBAC and security context
 * - Prepares for Tailscale-only access (no ingress)
 *
 * Note: This chart is primarily for CDK8s synthesis reference.
 * For initial bootstrap, use scripts/01-install-argocd.sh which
 * uses Helm CLI directly to break the chicken-and-egg problem.
 *
 * Helm Chart: https://github.com/argoproj/argo-helm
 * Docs: https://argo-cd.readthedocs.io/
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'yaml';

export interface ArgoCDHelmChartProps extends ChartProps {
  /**
   * ArgoCD Helm chart version
   * @default '7.3.0'
   */
  version?: string;

  /**
   * Namespace for ArgoCD deployment
   * @default 'argocd'
   */
  namespace?: string;

  /**
   * Number of ArgoCD server replicas
   * @default 3
   */
  serverReplicas?: number;

  /**
   * Enable high availability mode (Redis HA)
   * @default true
   */
  enableHA?: boolean;

  /**
   * Enable autoscaling for ArgoCD server
   * @default true
   */
  enableAutoscaling?: boolean;

  /**
   * Minimum replicas for autoscaling
   * @default 2
   */
  minReplicas?: number;

  /**
   * Maximum replicas for autoscaling
   * @default 5
   */
  maxReplicas?: number;

  /**
   * Enable ingress (disabled for Tailscale-only access)
   * @default false
   */
  enableIngress?: boolean;

  /**
   * Path to custom values file
   */
  valuesFile?: string;

  /**
   * Additional Helm values to merge
   */
  additionalValues?: Record<string, unknown>;
}

export class ArgoCDHelmChart extends Chart {
  constructor(scope: Construct, id: string, props: ArgoCDHelmChartProps = {}) {
    super(scope, id, props);

    const {
      version = '7.3.0',
      namespace = 'argocd',
      serverReplicas = 3,
      enableHA = true,
      enableAutoscaling = true,
      minReplicas = 2,
      maxReplicas = 5,
      enableIngress = false,
      valuesFile,
      additionalValues = {},
    } = props;

    // Load values from file if provided
    let fileValues: Record<string, unknown> = {};
    if (valuesFile) {
      try {
        const valuesPath = path.resolve(valuesFile);
        if (fs.existsSync(valuesPath)) {
          const content = fs.readFileSync(valuesPath, 'utf-8');
          fileValues = yaml.parse(content) || {};
        }
      } catch (e) {
        console.warn(`Could not load values file: ${valuesFile}`, e);
      }
    }

    // Build base values
    const baseValues: Record<string, unknown> = {
      // Global settings
      global: {
        domain: 'argocd.local',
      },

      // Redis configuration
      redis: {
        enabled: enableHA,
      },
      'redis-ha': {
        enabled: enableHA,
        haproxy: {
          enabled: enableHA,
          metrics: {
            enabled: true,
          },
        },
      },

      // Server configuration
      server: {
        replicas: serverReplicas,
        autoscaling: {
          enabled: enableAutoscaling,
          minReplicas: minReplicas,
          maxReplicas: maxReplicas,
          targetCPUUtilizationPercentage: 80,
          targetMemoryUtilizationPercentage: 80,
        },
        resources: {
          requests: {
            cpu: '100m',
            memory: '128Mi',
          },
          limits: {
            cpu: '500m',
            memory: '512Mi',
          },
        },
        service: {
          type: 'ClusterIP',
        },
        ingress: {
          enabled: enableIngress,
        },
        extraArgs: ['--insecure'], // TLS termination by Tailscale
        metrics: {
          enabled: true,
          serviceMonitor: {
            enabled: false,
          },
        },
      },

      // Controller configuration
      controller: {
        replicas: 1,
        resources: {
          requests: {
            cpu: '100m',
            memory: '256Mi',
          },
          limits: {
            cpu: '500m',
            memory: '1Gi',
          },
        },
        metrics: {
          enabled: true,
          serviceMonitor: {
            enabled: false,
          },
        },
      },

      // Repo server configuration
      repoServer: {
        replicas: 2,
        autoscaling: {
          enabled: true,
          minReplicas: 2,
          maxReplicas: 4,
          targetCPUUtilizationPercentage: 80,
        },
        resources: {
          requests: {
            cpu: '100m',
            memory: '128Mi',
          },
          limits: {
            cpu: '500m',
            memory: '512Mi',
          },
        },
        env: [
          {
            name: 'ARGOCD_EXEC_TIMEOUT',
            value: '3m',
          },
        ],
        metrics: {
          enabled: true,
          serviceMonitor: {
            enabled: false,
          },
        },
      },

      // ApplicationSet controller
      applicationSet: {
        enabled: true,
        replicas: 1,
        resources: {
          requests: {
            cpu: '50m',
            memory: '64Mi',
          },
          limits: {
            cpu: '200m',
            memory: '256Mi',
          },
        },
      },

      // Notifications
      notifications: {
        enabled: false,
      },

      // DEX (SSO)
      dex: {
        enabled: false,
      },

      // Config
      configs: {
        cm: {
          'statusbadge.enabled': 'true',
          'kustomize.buildOptions': '--enable-helm',
          'timeout.reconciliation': '180s',
        },
        rbac: {
          'policy.default': 'role:readonly',
          'policy.csv': `
# Admin can do everything
p, role:admin, *, *, *, allow

# Readonly can view
p, role:readonly, applications, get, *, allow
p, role:readonly, certificates, get, *, allow
p, role:readonly, clusters, get, *, allow
p, role:readonly, repositories, get, *, allow
p, role:readonly, projects, get, *, allow
p, role:readonly, accounts, get, *, allow
p, role:readonly, gpgkeys, get, *, allow
p, role:readonly, logs, get, *, allow

# Groups
g, admin, role:admin
          `.trim(),
        },
        secret: {
          createSecret: true,
        },
      },

      // CRDs
      crds: {
        install: true,
        keep: true,
      },
    };

    // Deep merge: base < file < additional
    const mergedValues = deepMerge(deepMerge(baseValues, fileValues), additionalValues);

    // Deploy ArgoCD using official Helm chart
    new Helm(this, 'argocd', {
      chart: 'argo-cd',
      repo: 'https://argoproj.github.io/argo-helm',
      version: version,
      namespace: namespace,
      releaseName: 'argocd',
      values: mergedValues,
    });
  }
}

/**
 * Deep merge two objects
 */
function deepMerge(target: Record<string, unknown>, source: Record<string, unknown>): Record<string, unknown> {
  const output = { ...target };

  for (const key of Object.keys(source)) {
    if (source[key] instanceof Object && key in target && target[key] instanceof Object) {
      output[key] = deepMerge(
        target[key] as Record<string, unknown>,
        source[key] as Record<string, unknown>
      );
    } else {
      output[key] = source[key];
    }
  }

  return output;
}
