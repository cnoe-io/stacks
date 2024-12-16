# Istio-Ambient Stack

This stack contains installation of Istio Ambient as well as supporting observability tooling so traffic, metrics, and traces can be observed


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

# Install istio along with observability components 

`idpbuilder create -p https://github.com/cnoe-io/stacks//isto-ambient/istio-base -p https://github.com/cnoe-io/stacks//isto-ambient/observability`


# Observability UIs

Kiali: https://kiali.cnoe.localtest.me:8443/

Grafana: https://grafana.cnoe.localtest.me:8443/

# Example Gateway and Application coming soon