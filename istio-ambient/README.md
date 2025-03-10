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

## Test Stack

Istio allows you to view in-depth network traffic. You can utilize this stack by creating the resources in this [sample file](istio-sample.yaml). It creates a couple of resources:
- ambient-test namesapce
- sleep nginx deployment
- nginx deployment
- nginx service

After you create these resources with the following command: 

`kubectl aply -f istio-sample.yaml`

You can then verify these resources with this command:

`kubectl -n ambient-test get all` 

Once the resources are created you can run the exec command to verify that the pods are running

`kubectl exec -n ambient-test deploy/sleep -- curl -v http://nginx`

View the logs that show the traffic

`kubectl logs -n istio-system -l app=ztunnel`