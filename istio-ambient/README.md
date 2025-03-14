# Istio-Ambient Stack

This stack contains installation of Istio Ambient as well as supporting observability tooling so traffic, metrics, and traces can be observed

Istio Ambient Mesh Docs: https://istio.io/latest/docs/ambient/overview/

Istio User Guides: https://istio.io/latest/docs/ambient/usage/

## Modules
- istio
  - installs istio ambient and no additional observability tooling

## Installation

# Install base istio with no observability

`idpbuilder create --package https://github.com/cnoe-io/stacks//istio-ambient/istio-ambient`

> [!NOTE]  
> Uses Default Mesh Configuration; user's can add an istio-configmap[1] to adjust configuration here if needed for testing 
> Refer to [the reference](https://github.com/cnoe-io/stacks/blob/main/ref-implementation/README.md#using-it) example which explains how to use each of the UI's that idpbuilder creates. Make sure each ArgoCD application is synced and healthy before proceeding.

[1]: https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/
