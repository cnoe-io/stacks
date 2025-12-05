/**
 * TailscaleIngressChart - Exposes services via Tailscale Operator Ingress
 *
 * This chart creates Kubernetes Ingress resources with ingressClassName: tailscale
 * which are processed by the Tailscale Operator to expose services on the tailnet.
 *
 * Benefits:
 * - Centralized certificate management (no Let's Encrypt rate limits)
 * - Automatic HTTPS with valid certificates
 * - Single operator manages all service proxies
 * - Standard Kubernetes Ingress API
 *
 * Prerequisites:
 * - Tailscale Operator deployed and running
 * - OAuth credentials configured
 *
 * Access: https://<hostname>.<tailnet>.ts.net
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * Configuration for a service to expose via Tailscale Ingress
 */
export interface TailscaleIngressServiceConfig {
  /**
   * Unique name for this ingress
   */
  name: string;

  /**
   * Namespace where the backend service lives
   */
  namespace: string;

  /**
   * Name of the Kubernetes service to expose
   */
  serviceName: string;

  /**
   * Port on the service (number or named port)
   */
  servicePort: number | string;

  /**
   * Tailscale hostname (without .ts.net suffix)
   * @default same as name
   */
  hostname?: string;

  /**
   * Tailscale tags for ACL control
   * @default ['tag:k8s']
   */
  tags?: string[];

  /**
   * Enable Tailscale Funnel (public internet access)
   * @default false
   */
  enableFunnel?: boolean;
}

export interface TailscaleIngressChartProps extends ChartProps {
  /**
   * Services to expose via Tailscale Ingress
   */
  services?: TailscaleIngressServiceConfig[];

  /**
   * Default Tailscale tags for all services
   * @default ['tag:k8s']
   */
  defaultTags?: string[];
}

/**
 * Default services to expose via Tailscale Ingress
 */
const DEFAULT_SERVICES: TailscaleIngressServiceConfig[] = [
  {
    name: 'argocd',
    namespace: 'argocd',
    serviceName: 'argocd-server',
    servicePort: 443,
    hostname: 'argocd',
  },
  {
    name: 'langfuse',
    namespace: 'observability',
    serviceName: 'langfuse',
    servicePort: 3000,
    hostname: 'langfuse',
  },
  {
    name: 'gitea',
    namespace: 'gitea',
    serviceName: 'my-gitea-http',
    servicePort: 3000,
    hostname: 'gitea',
  },
  {
    name: 'keycloak',
    namespace: 'keycloak',
    serviceName: 'keycloak',
    servicePort: 8080,
    hostname: 'keycloak',
  },
  {
    name: 'headlamp',
    namespace: 'headlamp',
    serviceName: 'headlamp',
    servicePort: 80,
    hostname: 'headlamp',
  },
  {
    name: 'kargo',
    namespace: 'kargo',
    serviceName: 'kargo-api',
    servicePort: 80,
    hostname: 'kargo',
  },
  {
    name: 'kagent',
    namespace: 'kagent',
    serviceName: 'kagent-ui',
    servicePort: 8080,
    hostname: 'kagent',
  },
];

export class TailscaleIngressChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleIngressChartProps = {}) {
    super(scope, id, props);

    const services = props.services || DEFAULT_SERVICES;
    const defaultTags = props.defaultTags || ['tag:k8s'];

    // Create Tailscale Ingress for each service
    services.forEach((svc) => {
      const hostname = svc.hostname || svc.name;
      const tags = svc.tags || defaultTags;

      // Build annotations for Tailscale operator
      const annotations: { [key: string]: string } = {
        'tailscale.com/hostname': hostname,
        'tailscale.com/tags': tags.join(','),
      };

      // Enable Funnel if requested (public internet access)
      if (svc.enableFunnel) {
        annotations['tailscale.com/funnel'] = 'true';
      }

      new k8s.KubeIngress(this, `ts-ingress-${svc.name}`, {
        metadata: {
          name: `ts-${svc.name}`,
          namespace: svc.namespace,
          annotations,
          labels: {
            'app.kubernetes.io/name': `ts-${svc.name}`,
            'app.kubernetes.io/component': 'tailscale-ingress',
            'app.kubernetes.io/part-of': 'tailscale',
            'app.kubernetes.io/managed-by': 'tailscale-operator',
          },
        },
        spec: {
          // Use Tailscale as the ingress class
          ingressClassName: 'tailscale',
          // Default backend for this service
          defaultBackend: {
            service: {
              name: svc.serviceName,
              port: typeof svc.servicePort === 'number'
                ? { number: svc.servicePort }
                : { name: svc.servicePort },
            },
          },
          // TLS configuration (Tailscale handles certs automatically)
          tls: [
            {
              hosts: [hostname],
            },
          ],
        },
      });
    });
  }
}
