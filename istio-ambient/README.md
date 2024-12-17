# Istio-Ambient Stack

This stack contains installation of Istio Ambient as well as supporting observability tooling so traffic, metrics, and traces can be observed

Istio Ambient Mesh Docs: https://istio.io/latest/docs/ambient/overview/



## Modules
- istio-base
  - installs istio ambient and no additional observability tooling
- observability
  - grafana - provides UI for tracing & prometheus metrics
    - tempo - collects traces for grafana
  - prometheus - required for kiali to display data
  - opentelemetry - used to collect traces from istio and forward to tempo

## Installation

# Install base istio with no observability

`idpbuilder create -p https://github.com/cnoe-io/stacks//isto-ambient/istio-base`

Uses istio's helmcharts to create an example istio ConfigMap, however the istio argo Application is set to ignore differences for this ConfigMap object, allowing users to adjust configuration here if needed for testing 

# Install istio along with observability components 

`idpbuilder create -p https://github.com/cnoe-io/stacks//isto-ambient/istio-base -p https://github.com/cnoe-io/stacks//isto-ambient/observability`


# Observability UIs

Kiali: https://kiali.cnoe.localtest.me:8443/

Grafana: https://grafana.cnoe.localtest.me:8443/

Path based routing using idpbuilder's `--use-path-routing` flag is not required and has not been tested

Path based routing and other traffic shaping can be setup using istio - gateway and application examples coming soon