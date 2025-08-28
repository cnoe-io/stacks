# KGateway Integration Guide

## Overview

This document describes the integration of KGateway into the CDK8s project, providing a centralized AI Gateway with MCP (Model Context Protocol) support for the platform.

## Architecture

### Host Cluster Deployment
KGateway is deployed in the host Kind cluster as a central resource, accessible from all VClusters (dev, staging). This architecture provides:

- **Centralized Management**: Single deployment serves all environments
- **Resource Efficiency**: Shared infrastructure reduces resource consumption
- **Unified Observability**: Central metrics and tracing for all AI traffic
- **Simplified Security**: Single point for authentication and authorization

### Component Structure

```
kgateway-system/
├── Controller (Helm)
├── GatewayClass
├── Gateway Resources
└── Service Endpoints

mcp-servers/
├── Grafana MCP Server
├── Echo MCP Server
├── Text Tools MCP Server
└── HTTPRoutes
```

## Implementation Components

### 1. Infrastructure Charts

#### KGatewayNamespaceChart
- **Location**: `charts/platform/kgateway-namespace-chart.ts`
- **Purpose**: Creates namespaces and RBAC resources
- **Sync Wave**: -100 (earliest)

#### KGatewayCRDsChart
- **Location**: `charts/platform/kgateway-crds-chart.ts`
- **Purpose**: Installs KGateway CRDs via Helm
- **Sync Wave**: -55

#### KGatewayHelmChart
- **Location**: `charts/platform/kgateway-helm-chart.ts`
- **Purpose**: Deploys KGateway controller via Helm
- **Sync Wave**: -50
- **Version**: v2.0.4 (stable)

#### KGatewayGatewayClassChart
- **Location**: `charts/platform/kgateway-gatewayclass-chart.ts`
- **Purpose**: Creates GatewayClass and default parameters
- **Sync Wave**: -45

### 2. MCP Server Charts

#### KGatewayMCPServersChart
- **Location**: `charts/platform/kgateway-mcp-servers-chart.ts`
- **Purpose**: Deploys MCP servers (Grafana, Echo, Text Tools)
- **Sync Wave**: 100
- **Features**:
  - SSE transport support
  - Health checks and readiness probes
  - Security context and resource limits
  - Network policies for access control

#### KGatewayMCPGatewayChart
- **Location**: `charts/platform/kgateway-mcp-gateway-chart.ts`
- **Purpose**: Creates Gateway resources for MCP and HTTP traffic
- **Sync Wave**: 110
- **Features**:
  - Dual gateway setup (MCP and HTTP)
  - TLS termination support
  - LoadBalancer service for VCluster access
  - CORS and security policies

#### KGatewayMCPRoutesChart
- **Location**: `charts/platform/kgateway-mcp-routes-chart.ts`
- **Purpose**: Defines HTTPRoute resources for MCP servers
- **Sync Wave**: 120
- **Routes**:
  - `/mcp/grafana` → Grafana MCP server
  - `/mcp/echo` → Echo test server
  - `/mcp/text-tools` → Text manipulation tools
  - `/mcp/discovery` → Server discovery endpoint
  - `/health` → Health check endpoint

## Configuration

### Application Configuration
All KGateway applications are registered in `config/applications.ts`:

```typescript
{
  name: 'kgateway-namespace',
  namespace: 'kgateway-system',
  chart: { type: 'KGatewayNamespaceChart' },
  argocd: {
    syncWave: '-100',
    syncPolicy: automatedSyncWithOptions(['CreateNamespace=true'])
  }
}
```

### Chart Registration
Charts are registered in `main-v2.ts`:

```typescript
IdpBuilderChartFactory.register('KGatewayNamespaceChart', KGatewayNamespaceChart);
IdpBuilderChartFactory.register('KGatewayCRDsChart', KGatewayCRDsChart);
// ... additional charts
```

## Access Patterns

### From Host Cluster
```bash
# Direct service access
curl http://mcp-gateway.kgateway-system.svc.cluster.local:8080/mcp/echo
```

### From VClusters
```bash
# Via LoadBalancer service
curl http://mcp-gateway.kgateway-system:8080/mcp/grafana

# Via Ingress
curl https://mcp-gateway.cnoe.localtest.me:8443/mcp/text-tools
```

### From External Clients
```bash
# Via Ingress with TLS
curl https://kgateway.cnoe.localtest.me/health
```

## Security Features

### Network Policies
- Restricts MCP server access to KGateway proxies
- Allows metrics scraping from monitoring namespace
- Enforces pod-to-pod communication rules

### RBAC
- ServiceAccounts for controller and proxy pods
- ClusterRoles with minimal required permissions
- Namespace-scoped roles for local resources

### Pod Security
- Non-root user execution (UID 10001)
- Read-only root filesystem
- Dropped capabilities
- Seccomp profiles

## Observability

### Metrics
- Prometheus endpoints on port 9090
- ServiceMonitor resources for scraping
- Custom metrics for MCP traffic

### Tracing
- OpenTelemetry integration
- Trace propagation (W3C, B3)
- Configurable sampling rates

### Logging
- JSON structured logs
- Configurable log levels
- Privacy-preserving defaults

## Deployment

### Synthesis
```bash
cd /home/vpittamp/stacks/cdk8s
npm run synth
```

### Deployment via IdpBuilder
```bash
# Deploy all KGateway components
idpbuilder create -p dist/kgateway-namespace
idpbuilder create -p dist/kgateway-crds
idpbuilder create -p dist/kgateway-helm
idpbuilder create -p dist/kgateway-gatewayclass
idpbuilder create -p dist/kgateway-mcp-servers
idpbuilder create -p dist/kgateway-mcp-gateway
idpbuilder create -p dist/kgateway-mcp-routes
```

### Verification
```bash
# Check pods
kubectl get pods -n kgateway-system
kubectl get pods -n mcp-servers

# Check gateways
kubectl get gateways -n kgateway-system

# Check routes
kubectl get httproutes -A

# Test MCP endpoint
curl http://mcp-gateway.cnoe.localtest.me:8080/health
```

## Integration Points

### Kagent Integration
Kagent agents can use KGateway MCP endpoints via ToolServer resources:

```yaml
apiVersion: kagent.dev/v1alpha1
kind: ToolServer
metadata:
  name: grafana-tools
spec:
  endpoint: http://mcp-gateway.kgateway-system:8080/mcp/grafana
  transport: sse
```

### External Secrets
GitHub tokens and API keys are managed via External Secrets Operator:

```yaml
secretStoreRef:
  name: azure-keyvault-store
  kind: ClusterSecretStore
```

### Monitoring Stack
Integration with existing Grafana/Prometheus:
- Metrics exported to Prometheus
- Dashboards available in Grafana
- Traces sent to Alloy/Tempo

## Troubleshooting

### Common Issues

1. **Pods not starting**: Check RBAC and namespace creation
2. **Routes not working**: Verify ReferenceGrant resources
3. **VCluster access denied**: Check LoadBalancer service and network policies
4. **MCP servers unhealthy**: Review health check endpoints and probes

### Debug Commands

```bash
# Check controller logs
kubectl logs -n kgateway-system -l app.kubernetes.io/name=kgateway

# Describe gateway
kubectl describe gateway -n kgateway-system mcp-gateway

# Check route status
kubectl get httproute -n mcp-servers grafana-mcp -o yaml

# Test MCP server directly
kubectl port-forward -n mcp-servers svc/grafana-mcp 8080:8080
curl http://localhost:8080/health
```

## Future Enhancements

1. **Additional MCP Servers**: Add more AI tool servers as they become available
2. **Authentication**: Implement OAuth2/OIDC for external access
3. **Rate Limiting**: Add per-client rate limiting policies
4. **Caching**: Implement response caching for frequently used tools
5. **Multi-region**: Deploy across multiple clusters with federation

## References

- [KGateway Documentation](https://kgateway.dev/docs/)
- [Gateway API Specification](https://gateway-api.sigs.k8s.io/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [CDK8s Documentation](https://cdk8s.io/)