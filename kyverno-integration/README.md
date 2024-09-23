# Kyverno Stack

Implementation of Kyverno for CNOE

## Components

The Stack installs `Kyverno` and `Kyverno Pod Security Policies - Restricted` implementation. By default users should use:
  - `kyverno-pss-policies-audit.yaml` - for testing and understanding of the impact
  - `kyverno-pss-policies-enforce.yaml` - once the proper state of platform is understood and all necessary workload exceptions or violations have been accounted for.
    - If you chose to enable `Enforce` mode. Exceptions for the following `ref-implementation` components are included, to ensure proper operability:
      - [ArgoCD](exceptions/argocd.yaml)
      - [Crossplane](exceptions/crossplane.yaml)
      - [Backstage](exceptions/backstage.yaml)
      - [Ingress-Nginx](exceptions/ingress-nginx.yaml)
      - [Kind cluster](exceptions/kind.yaml), this should mainly be needed when testing `ref-implementation` on a `kind` installation

*NOTE* - enabling `Enforce` mode without prior testing will most likely cause issues, always start with `Audit` unless you are completely sure of the impact enabling blocking policies will have on your platform.

## Installation
