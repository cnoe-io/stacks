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

You can use and test out this stack without using any policies, using the `ref-implementation` as follows:

```bash
idpbuilder create --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation
  -p https://github.com/cnoe-io/stacks//kyverno-integration
```

Depending on your use case, install the Kubernetes PSS Policies, implemented in Kyverno as follows:

```bash
git clone https://github.com/cnoe-io/stacks.git
cd stacks

idpbuilder create --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation
  -p https://github.com/cnoe-io/stacks//kyverno-integration
  -p kyverno-integration/manifests/kyverno-pss-policies-audit.yaml
```

If you would like to change to `Enforce` mode, replace with `-p kyverno-integration/manifests/kyverno-pss-policies-audit.yaml` and add the provided exceptions to the installation.

```bash
git clone https://github.com/cnoe-io/stacks.git
cd stacks

idpbuilder create --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation
  -p https://github.com/cnoe-io/stacks//kyverno-integration
  -p kyverno-integration/manifests/kyverno-pss-policies-enforce.yaml
  -p kyverno-integration/manifests/exceptions
```
