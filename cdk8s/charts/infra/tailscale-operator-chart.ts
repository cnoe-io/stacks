/**
 * TailscaleOperatorChart - Deploys the Tailscale Kubernetes Operator via Helm
 *
 * This chart deploys the official Tailscale Kubernetes Operator which:
 * - Manages Tailscale resources (ProxyGroup, Connector, DNSConfig)
 * - Provides ingressClassName: tailscale for exposing services
 * - Centralizes certificate management (avoiding Let's Encrypt rate limits)
 * - Handles state persistence automatically
 *
 * Prerequisites:
 * - OAuth credentials synced to 'operator-oauth' secret (with keys 'client_id' and 'client_secret')
 * - Tailscale ACL policy with tag:k8s-operator configured
 *
 * Helm Chart: https://pkgs.tailscale.com/helmcharts (tailscale-operator)
 * Docs: https://tailscale.com/kb/1236/kubernetes-operator
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';

export interface TailscaleOperatorChartProps extends ChartProps {
  /**
   * Tailscale Operator Helm chart version
   * @default '1.82.0'
   */
  version?: string;

  /**
   * Namespace for operator deployment
   * @default 'tailscale'
   */
  namespace?: string;

  /**
   * Hostname for the operator (used for APISERVER_PROXY mode)
   * @default 'kind-operator'
   */
  operatorHostname?: string;

  /**
   * Default tags for operator-created devices
   * @default ['tag:k8s']
   */
  defaultTags?: string[];

  /**
   * Enable APISERVER_PROXY mode for kubectl access
   * @default false
   */
  enableApiServerProxy?: boolean;

  /**
   * Log level for operator
   * @default 'info'
   */
  logLevel?: string;
}

export class TailscaleOperatorChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleOperatorChartProps = {}) {
    super(scope, id, props);

    const {
      version = '1.82.0',
      namespace = 'tailscale',
      operatorHostname = 'kind-operator',
      defaultTags = ['tag:k8s'],
      enableApiServerProxy = false,
      logLevel = 'info',
    } = props;

    // Deploy Tailscale Operator using official Helm chart
    // Note: Tailscale uses traditional Helm repo, not OCI registry
    // Repo: https://pkgs.tailscale.com/helmcharts
    new Helm(this, 'tailscale-operator', {
      chart: 'tailscale-operator',
      repo: 'https://pkgs.tailscale.com/helmcharts',
      version: version,
      namespace: namespace,
      releaseName: 'tailscale-operator',
      values: {
        // CRDs are managed separately by tailscale-crds app (sync wave -120)
        // This avoids version drift between Helm chart CRDs and latest CRDs
        installCRDs: false,

        // Operator configuration
        operatorConfig: {
          hostname: operatorHostname,
          logging: logLevel,
          defaultTags: defaultTags,
        },

        // OAuth credentials - leave empty, uses default secret 'operator-oauth' with keys 'client_id' and 'client_secret'
        // The secret is created by TailscaleOperatorSecretsChart via ExternalSecret
        oauth: {},

        // Proxy configuration for operator-managed proxies
        proxyConfig: {
          image: {
            repository: 'tailscale/tailscale',
            tag: 'latest',
          },
          // defaultTags must be a comma-separated string for proxies
          defaultTags: defaultTags.join(','),
        },

        // API server proxy mode (for remote kubectl access)
        apiServerProxyConfig: {
          mode: enableApiServerProxy ? 'true' : 'noauth',
        },

        // Operator deployment resources
        resources: {
          requests: {
            cpu: '100m',
            memory: '128Mi',
          },
          limits: {
            cpu: '500m',
            memory: '256Mi',
          },
        },

        // Service account configuration
        serviceAccount: {
          create: true,
          name: 'tailscale-operator',
        },

        // RBAC
        rbac: {
          create: true,
        },

        // Security context - allow running as root for network access
        podSecurityContext: {
          runAsNonRoot: false,
        },

        // Tolerations for control plane nodes if needed
        tolerations: [],

        // Node selector
        nodeSelector: {},
      },
    });
  }
}
