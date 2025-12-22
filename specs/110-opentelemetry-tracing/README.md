# OpenTelemetry Tracing Integration (Spec 110)

This specification covers the integration of OpenTelemetry (OTel) between NixOS hosts and the Kubernetes cluster for centralized logging, metrics, and tracing.

## Architecture

1.  **NixOS Side**:
    *   **AI Assistants (Claude Code, etc.)** emit OTLP telemetry to `localhost:4318`.
    *   **Local OTel Collector**:
        *   Receives telemetry on port 4318.
        *   Forwards to `otel-ai-monitor` user service (port 4320) for local session tracking/EWW widgets.
        *   **NEW**: Exports to the Kubernetes OTel stack via Tailscale.
2.  **Kubernetes Side**:
    *   **Tailscale Services**: Exposes the OTel Collector at `https://otel-collector-<cluster>.tail286401.ts.net` (tcp:443).
    *   **OTel Collector (Cluster)**: Receives telemetry from external hosts and internal pods.
    *   **ClickHouse**: High-performance persistence layer for traces, metrics, and logs.
    *   **Grafana**: Visualization dashboard with ClickHouse datasource (exposed via Tailscale).

## Implementation Details

### Kubernetes Components (cdk8s)

*   **Chart**: `cdk8s/charts/infra/otel-stack-chart.ts`
*   **Applications**:
    *   `otel-stack`: ClickHouse + OTel Collector + Grafana.
    *   `otel-collector-tailscale-serve`: Public (tailnet) endpoint for the collector.
    *   `grafana-tailscale-serve`: Public (tailnet) access to dashboards.

### NixOS Components

*   **Module**: `modules/services/otel-ai-collector.nix`
*   **New Options**:
    *   `services.otel-ai-collector.enableK8sExporter`: Defaults to `true`.
    *   `services.otel-ai-collector.k8sExporterEndpoint`: Defaults to `https://otel-collector-<cluster>.tail286401.ts.net`.

## Accessing the Data

1.  **Grafana**: [https://grafana-<cluster>.tail286401.ts.net](https://grafana-ryzen.tail286401.ts.net)
    *   Datasource: ClickHouse
    *   Pre-configured with anonymous Admin access for ease of use.
2.  **OTel Collector**: [https://otel-collector-<cluster>.tail286401.ts.net](https://otel-collector-ryzen.tail286401.ts.net)

## Verification Steps

1.  Run `cd cdk8s && npm run synth` to ensure manifests are valid.
2.  Deploy to cluster: `idpbuilder create --package cdk8s/dist/`.
3.  Apply NixOS configuration on the host: `sudo nixos-rebuild switch`.
4.  Generate telemetry (e.g., run a Claude Code command).
5.  Check Grafana for incoming traces/logs.
