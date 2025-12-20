/**
 * LgtmGrafanaChart - Grafana Deployment for LGTM Stack Visualization
 *
 * Deploys Grafana with pre-configured LGTM datasources (Mimir, Loki, Tempo, Pyroscope).
 * Includes trace-to-logs and logs-to-traces correlation.
 *
 * Feature: 111-configure-k8s-observability
 * Sync wave: -50 (after backends and collector)
 *
 * Ports:
 * - 3000: HTTP UI
 *
 * Endpoints:
 * - UI: http://grafana:3000
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  LGTM_NAMESPACE,
  LGTM_IMAGES,
  LGTM_RESOURCES,
  getLgtmComponentLabels,
  getLgtmSelectorLabels,
  toK8sResources,
  generateGrafanaDatasources,
  generateDashboardConfigs,
  GRAFANA_COMMUNITY_DASHBOARDS,
} from '../../lib/lgtm-helpers';

export interface LgtmGrafanaChartProps extends ChartProps {
  /**
   * Namespace for Grafana deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Grafana container image
   * @default 'grafana/grafana:11.3.0'
   */
  image?: string;

  /**
   * Mimir Prometheus API URL
   * @default 'http://mimir:9009/prometheus'
   */
  mimirUrl?: string;

  /**
   * Loki API URL
   * @default 'http://loki:3100'
   */
  lokiUrl?: string;

  /**
   * Tempo API URL
   * @default 'http://tempo:3200'
   */
  tempoUrl?: string;

  /**
   * Pyroscope API URL
   * @default 'http://pyroscope:4040'
   */
  pyroscopeUrl?: string;

  /**
   * Resource requests and limits
   */
  resources?: {
    requests?: { cpu?: string; memory?: string };
    limits?: { cpu?: string; memory?: string };
  };
}

export class LgtmGrafanaChart extends Chart {
  constructor(scope: Construct, id: string, props?: LgtmGrafanaChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || LGTM_NAMESPACE;
    const image = props?.image || LGTM_IMAGES.grafana;
    const mimirUrl = props?.mimirUrl || 'http://mimir:9009/prometheus';
    const lokiUrl = props?.lokiUrl || 'http://loki:3100';
    const tempoUrl = props?.tempoUrl || 'http://tempo:3200';
    const pyroscopeUrl = props?.pyroscopeUrl || 'http://pyroscope:4040';
    const resources = props?.resources || LGTM_RESOURCES.grafana;

    const labels = getLgtmComponentLabels('grafana', 'visualization');
    const selectorLabels = getLgtmSelectorLabels('grafana');

    // ConfigMap with Grafana datasources provisioning
    const datasourcesConfig = generateGrafanaDatasources(mimirUrl, lokiUrl, tempoUrl, pyroscopeUrl);

    new k8s.KubeConfigMap(this, 'datasources', {
      metadata: {
        name: 'grafana-datasources',
        namespace,
        labels,
      },
      data: {
        'datasources.yaml': JSON.stringify(datasourcesConfig, null, 2),
      },
    });

    // ConfigMap with dashboard providers
    const dashboardProviders = {
      apiVersion: 1,
      providers: [
        {
          name: 'Custom',
          orgId: 1,
          folder: 'Custom',
          folderUid: 'custom',
          type: 'file',
          disableDeletion: false,
          editable: true,
          updateIntervalSeconds: 30,
          options: {
            path: '/var/lib/grafana/dashboards/custom',
          },
        },
        {
          name: 'Community',
          orgId: 1,
          folder: 'Community',
          folderUid: 'community',
          type: 'file',
          disableDeletion: false,
          editable: true,
          updateIntervalSeconds: 30,
          options: {
            path: '/var/lib/grafana/dashboards/community',
          },
        },
      ],
    };

    new k8s.KubeConfigMap(this, 'dashboard-providers', {
      metadata: {
        name: 'grafana-dashboard-providers',
        namespace,
        labels,
      },
      data: {
        'dashboards.yaml': JSON.stringify(dashboardProviders, null, 2),
      },
    });

    // ConfigMap with custom dashboards (GenAI, LGTM Overview)
    const customDashboards = generateDashboardConfigs();
    new k8s.KubeConfigMap(this, 'custom-dashboards', {
      metadata: {
        name: 'grafana-dashboards-custom',
        namespace,
        labels,
      },
      data: customDashboards,
    });

    // ConfigMap with download script for community dashboards
    // Generate individual download commands for each dashboard
    const communityDashboards = GRAFANA_COMMUNITY_DASHBOARDS;
    const downloadCommands = Object.values(communityDashboards)
      .map(d => {
        const name = d.name.replace(/\s+/g, '-').toLowerCase();
        return `echo "Downloading ${name} (ID: ${d.id}, Rev: ${d.revision})..."
wget -q -O "/dashboards/${name}.json" "https://grafana.com/api/dashboards/${d.id}/revisions/${d.revision}/download" || echo "Failed to download ${name}"`;
      })
      .join('\n');

    const downloadScript = `#!/bin/sh
set -e
mkdir -p /dashboards
echo "Downloading community dashboards from Grafana.com..."

${downloadCommands}

echo "Dashboard download complete."
ls -la /dashboards/
`;

    new k8s.KubeConfigMap(this, 'dashboard-downloader', {
      metadata: {
        name: 'grafana-dashboard-downloader',
        namespace,
        labels,
      },
      data: {
        'download-dashboards.sh': downloadScript,
      },
    });

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'grafana',
        namespace,
        labels,
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: selectorLabels },
        template: {
          metadata: { labels },
          spec: {
            securityContext: {
              fsGroup: 472,
              runAsUser: 472,
              runAsNonRoot: true,
            },
            initContainers: [
              {
                name: 'download-dashboards',
                image: 'busybox:1.36',
                command: ['sh', '/scripts/download-dashboards.sh'],
                volumeMounts: [
                  {
                    name: 'dashboard-downloader',
                    mountPath: '/scripts',
                  },
                  {
                    name: 'community-dashboards',
                    mountPath: '/dashboards',
                  },
                ],
                securityContext: {
                  runAsUser: 472,
                  runAsNonRoot: true,
                },
              },
            ],
            containers: [
              {
                name: 'grafana',
                image,
                ports: [
                  { containerPort: 3000, name: 'http' },
                ],
                env: [
                  // Anonymous access for homelab (internal via Tailscale)
                  { name: 'GF_AUTH_ANONYMOUS_ENABLED', value: 'true' },
                  { name: 'GF_AUTH_ANONYMOUS_ORG_ROLE', value: 'Admin' },
                  // Install Pyroscope plugin
                  { name: 'GF_INSTALL_PLUGINS', value: 'grafana-pyroscope-app' },
                  // Enable tracing features
                  { name: 'GF_FEATURE_TOGGLES_ENABLE', value: 'traceToLogs,traceToMetrics,traceToProfiles' },
                ],
                volumeMounts: [
                  {
                    name: 'datasources',
                    mountPath: '/etc/grafana/provisioning/datasources',
                  },
                  {
                    name: 'dashboard-providers',
                    mountPath: '/etc/grafana/provisioning/dashboards',
                  },
                  {
                    name: 'custom-dashboards',
                    mountPath: '/var/lib/grafana/dashboards/custom',
                  },
                  {
                    name: 'community-dashboards',
                    mountPath: '/var/lib/grafana/dashboards/community',
                  },
                ],
                resources: toK8sResources(resources),
                readinessProbe: {
                  httpGet: {
                    path: '/api/health',
                    port: k8s.IntOrString.fromNumber(3000),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/api/health',
                    port: k8s.IntOrString.fromNumber(3000),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                },
              },
            ],
            volumes: [
              {
                name: 'datasources',
                configMap: { name: 'grafana-datasources' },
              },
              {
                name: 'dashboard-providers',
                configMap: { name: 'grafana-dashboard-providers' },
              },
              {
                name: 'custom-dashboards',
                configMap: { name: 'grafana-dashboards-custom' },
              },
              {
                name: 'dashboard-downloader',
                configMap: {
                  name: 'grafana-dashboard-downloader',
                  defaultMode: 0o755,
                },
              },
              {
                name: 'community-dashboards',
                emptyDir: {},
              },
            ],
          },
        },
      },
    });

    // Service - Port 80 externally maps to 3000 internally (matching existing otel-stack pattern)
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'grafana',
        namespace,
        labels,
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 80,
            targetPort: k8s.IntOrString.fromNumber(3000),
          },
        ],
        selector: selectorLabels,
      },
    });
  }
}
