# ArgoCD Configuration
# IDPBuilder manages ArgoCD directly - no nixidy app needed.
#
# For ArgoCD performance tuning, use idpBuilder's override mechanism:
# idpbuilder create -c argocd:/path/to/argocd-cm-override.yaml
# See: https://cnoe.io/docs/idpbuilder/override
#
# Example performance settings (add to argocd-cmd-params-cm):
#   controller.status.processors: "50"
#   controller.operation.processors: "25"
#   controller.kubectl.parallelism.limit: "20"
#   timeout.reconciliation: "60s"
#   controller.diff.server.side: "true"
#
# This file intentionally empty - idpBuilder owns ArgoCD.
{ config, lib, ... }:
{
  # No applications defined - ArgoCD is managed by idpBuilder
}
