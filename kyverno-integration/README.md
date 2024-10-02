# Kyverno Stack

Implementation of Kyverno for CNOE

## Components

The Stack installs `Kyverno` and optionally `Kyverno Pod Security Policies - Restricted` implementation. By default users should use:
  - `module/audit` - for testing and understanding of the impact
  - `module/enforce` - once the proper state of platform is understood and all necessary workload exceptions or violations have been accounted for.
    - If you chose to enable `Enforce` mode. Exceptions for the following `ref-implementation` components are included, to ensure proper operability:
      - [ArgoCD](modules/enforce/exceptions/argocd.yaml)
      - [Crossplane](modules/enforce/exceptions/crossplane.yaml)
      - [Backstage](modules/enforce/exceptions/backstage.yaml)
      - [Ingress-Nginx](modules/enforce/exceptions/ingress-nginx.yaml)
      - [Kind cluster](modules/enforce/exceptions/kind.yaml), this should mainly be needed when testing `ref-implementation` on a `kind` installation

*NOTE* - enabling `Enforce` mode without prior testing will most likely cause issues for NEW workloads, already existing workloads will not be affected immediately, always start with `Audit` unless you are completely sure of the impact enabling blocking policies will have on your platform.

## Installation

You can use and test out this stack without using any policies, using the `ref-implementation` as follows:

```bash
idpbuilder create --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation \
  -p https://github.com/cnoe-io/stacks//kyverno-integration
```

Depending on your use case, install the Kubernetes PSS Policies in `Audit`, implemented in Kyverno as follows:

```bash
idpbuilder create --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation \
  -p https://github.com/cnoe-io/stacks//kyverno-integration \
  -p https://github.com/cnoe-io/stacks//kyverno-integration/modules/audit
```

If you would like to change to `Enforce` mode:

```bash
idpbuilder create --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation \
  -p https://github.com/cnoe-io/stacks//kyverno-integration \
  -p https://github.com/cnoe-io/stacks//kyverno-integration/modules/enforce
```

