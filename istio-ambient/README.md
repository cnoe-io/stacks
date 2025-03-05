# Istio-Ambient Stack

This stack contains installation of Istio Ambient as well as supporting observability tooling so traffic, metrics, and traces can be observed

Istio Ambient Mesh Docs: https://istio.io/latest/docs/ambient/overview/



## Modules
- istio
  - installs istio ambient and no additional observability tooling

## Installation

# Install base istio with no observability

`idpbuilder create -p https://github.com/cnoe-io/stacks//istio-ambient/istio-ambient`

Uses Default Mesh Configuration; user's can add an istio-configmap[1] to adjust configuration here if needed for testing 

[1]: https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/
