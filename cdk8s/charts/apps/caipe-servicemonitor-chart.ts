/**
 * CaipeServiceMonitorChart - Prometheus ServiceMonitors for CAIPE
 *
 * Creates ServiceMonitor resources for Prometheus to scrape metrics from:
 * - Supervisor Agent (port 8000 /metrics)
 * - RAG components that expose metrics
 *
 * Requires Prometheus Operator to be installed in the cluster.
 */

import { Chart, ChartProps, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  getCaipeCommonLabels,
} from '../../lib/caipe-helpers';

export interface CaipeServiceMonitorChartProps extends ChartProps {
  /**
   * Namespace for CAIPE ServiceMonitors
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '110'
   */
  syncWave?: string;

  /**
   * Scrape interval
   * @default '30s'
   */
  scrapeInterval?: string;
}

export class CaipeServiceMonitorChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeServiceMonitorChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const syncWave = props.syncWave || '110';
    const scrapeInterval = props.scrapeInterval || '30s';

    const commonLabels = getCaipeCommonLabels('servicemonitor');

    // ==========================================================================
    // ServiceMonitor for Supervisor Agent
    // ==========================================================================
    // Scrapes metrics from the supervisor-agent on port 8000
    new ApiObject(this, 'supervisor-agent-servicemonitor', {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'caipe-supervisor-agent',
        namespace: namespace,
        labels: {
          ...commonLabels,
          'app.kubernetes.io/component': 'supervisor-agent',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': 'supervisor-agent',
          },
        },
        namespaceSelector: {
          matchNames: [namespace],
        },
        endpoints: [
          {
            port: 'http',
            path: '/metrics',
            interval: scrapeInterval,
            scrapeTimeout: '10s',
          },
        ],
      },
    });

    // ==========================================================================
    // ServiceMonitor for all CAIPE Agents
    // ==========================================================================
    // Scrapes metrics from all sub-agents (argocd, github, backstage)
    new ApiObject(this, 'agents-servicemonitor', {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'caipe-agents',
        namespace: namespace,
        labels: {
          ...commonLabels,
          'app.kubernetes.io/component': 'agents',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: {
          matchLabels: {
            'tier': 'agent',
          },
        },
        namespaceSelector: {
          matchNames: [namespace],
        },
        endpoints: [
          {
            port: 'mcp-http',
            path: '/metrics',
            interval: scrapeInterval,
            scrapeTimeout: '10s',
          },
        ],
      },
    });

    // ==========================================================================
    // ServiceMonitor for RAG Components
    // ==========================================================================
    // Scrapes metrics from rag-server and nexigraph
    new ApiObject(this, 'rag-servicemonitor', {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'caipe-rag',
        namespace: namespace,
        labels: {
          ...commonLabels,
          'app.kubernetes.io/component': 'rag',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: {
          matchLabels: {
            'tier': 'rag',
          },
        },
        namespaceSelector: {
          matchNames: [namespace],
        },
        endpoints: [
          {
            port: 'http',
            path: '/metrics',
            interval: scrapeInterval,
            scrapeTimeout: '10s',
          },
        ],
      },
    });
  }
}
