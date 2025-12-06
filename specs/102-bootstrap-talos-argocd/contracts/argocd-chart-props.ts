/**
 * Contract: ArgoCD CDK8s Chart Properties
 * Feature: 102-bootstrap-talos-argocd
 *
 * Defines the TypeScript interfaces for ArgoCD-related CDK8s charts.
 */

import { ChartProps } from 'cdk8s';

/**
 * Properties for the ArgoCD Helm Chart
 */
export interface ArgoCDHelmChartProps extends ChartProps {
  /**
   * Helm chart version to install
   * @default '7.3.0'
   */
  version?: string;

  /**
   * Number of ArgoCD server replicas
   * @default 3
   */
  replicaCount?: number;

  /**
   * Enable high availability mode
   * @default true
   */
  enableHA?: boolean;

  /**
   * Enable autoscaling for ArgoCD server
   */
  autoscaling?: {
    enabled: boolean;
    minReplicas: number;
    maxReplicas: number;
    targetCPUUtilizationPercentage?: number;
  };

  /**
   * ArgoCD server ingress configuration (disabled for Tailscale-only access)
   */
  ingress?: {
    enabled: boolean;
    hostname?: string;
    tls?: boolean;
  };

  /**
   * Additional Helm values to merge
   */
  additionalValues?: Record<string, unknown>;
}

/**
 * Properties for the ArgoCD Root Application (App-of-Apps)
 */
export interface ArgoCDRootApplicationChartProps extends ChartProps {
  /**
   * Git repository URL for ArgoCD to sync from
   */
  repoUrl: string;

  /**
   * Path in repository containing child application manifests
   * @default 'cdk8s/dist/platform/manifests'
   */
  path?: string;

  /**
   * Git reference (branch, tag, or commit)
   * @default 'main'
   */
  targetRevision?: string;

  /**
   * ArgoCD project to use
   * @default 'default'
   */
  project?: string;

  /**
   * Enable automated sync with prune
   * @default true
   */
  enableAutomatedSync?: boolean;

  /**
   * Enable self-heal (auto-sync on drift)
   * @default true
   */
  enableSelfHeal?: boolean;

  /**
   * Sync wave for the root application
   * @default '-50'
   */
  syncWave?: string;
}

/**
 * Properties for individual ArgoCD Application resources
 */
export interface ArgoCDApplicationChartProps extends ChartProps {
  /**
   * Application name (must be unique in ArgoCD namespace)
   */
  appName: string;

  /**
   * Target namespace for the application resources
   */
  targetNamespace: string;

  /**
   * Git repository URL
   */
  repoUrl: string;

  /**
   * Path in repository
   */
  path: string;

  /**
   * Git reference
   * @default 'main'
   */
  targetRevision?: string;

  /**
   * ArgoCD project
   * @default 'default'
   */
  project?: string;

  /**
   * Sync wave for ordering
   */
  syncWave?: string;

  /**
   * Sync policy configuration
   */
  syncPolicy?: {
    automated?: {
      prune: boolean;
      selfHeal: boolean;
    };
    syncOptions?: string[];
  };

  /**
   * Ignore differences for specific fields
   */
  ignoreDifferences?: Array<{
    group: string;
    kind: string;
    jsonPointers?: string[];
    jqPathExpressions?: string[];
  }>;
}

/**
 * Sync wave constants for bootstrap ordering
 */
export const SYNC_WAVES = {
  /** Foundation: CNI, critical infrastructure */
  FOUNDATION: '-110',

  /** Operators: ESO, Tailscale */
  OPERATORS: '-100',

  /** Identity: Workload Identity patches */
  IDENTITY: '-94',

  /** Stores: ClusterSecretStore */
  STORES: '-92',

  /** Secrets: ExternalSecrets for auth */
  SECRETS: '-85',

  /** Access: Tailscale operator */
  ACCESS: '-80',

  /** Services: Tailscale serve pods */
  SERVICES: '-60',

  /** Platform: Self-managed ArgoCD */
  PLATFORM: '0',

  /** Applications: User workloads */
  APPLICATIONS: '10',
} as const;
