import { Chart, ChartProps, Include } from 'cdk8s';
import { Construct } from 'constructs';

/**
 * GatewayApiCrdsChart installs the standard Kubernetes Gateway API CRDs
 * This must be installed before kgateway or any Gateway API resources
 * 
 * Uses the standard channel which includes stable GA/beta resources:
 * - GatewayClass
 * - Gateway  
 * - HTTPRoute
 * - GRPCRoute
 * - ReferenceGrant
 */
export class GatewayApiCrdsChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);
    
    // Include Gateway API v1.2.1 standard CRDs
    // This downloads and includes the official CRDs from the Gateway API project
    new Include(this, 'gateway-api-crds', {
      url: 'https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml'
    });
  }
}