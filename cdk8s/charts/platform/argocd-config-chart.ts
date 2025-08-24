import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

/**
 * ArgoCD Configuration Chart
 * Provides custom health checks and other ArgoCD configurations
 */
export class ArgoCDConfigChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    // Create ConfigMap for ArgoCD custom health checks
    // This merges with the existing argocd-cm ConfigMap
    // Note: In production, this should be applied as a patch to the existing ConfigMap
    // For now, we create it separately and rely on ArgoCD's merge behavior
    new k8s.KubeConfigMap(this, 'argocd-cm-health-customizations', {
      metadata: {
        name: 'argocd-cm',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100', // Apply early
          'argocd.argoproj.io/sync-options': 'Replace=false', // Don't replace, merge
        },
      },
      data: {
        // Custom health check for Ingress - always consider healthy
        'resource.customizations.health.networking.k8s.io_Ingress': `hs = {}
hs.status = "Healthy"
hs.message = "Ingress is always considered healthy to prevent sync deadlocks"
return hs`,
        
        // Optional: Add more custom health checks here if needed
        // For example, for PVCs that might take time to bind:
        'resource.customizations.health.v1_PersistentVolumeClaim': `hs = {}
if obj.status ~= nil then
  if obj.status.phase ~= nil then
    if obj.status.phase == "Pending" then
      hs.status = "Progressing"
      hs.message = "PVC is pending"
    elseif obj.status.phase == "Bound" then
      hs.status = "Healthy"
      hs.message = "PVC is bound"
    else
      hs.status = "Degraded"
      hs.message = "PVC is in " .. obj.status.phase .. " phase"
    end
  end
end
return hs`,
      },
    });
  }
}