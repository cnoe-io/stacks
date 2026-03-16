
# Observability Stack

This directory contains an observability implementation based on Grafana tooling

## Caveats
1) reliance on ref-implementation for SSO
   - This is possible to work around by removing the `auth.generic_oauth` section from `prometheus.yaml` and removing the `grafana-config.yaml` and `grafana-external-secret.yaml` files
2) using `tls_skip_verify_insecure` for oauth
    - This is due to using the ingress certificate. Once this is addressed, we can remove this
3) Bigger memory requirement required for kind cluster
    - Due to using a more robust loki deployment, the memory limits have been increased. 16 GB seems to work while leaving ample room in the cluster. 

## Components
The observability stack is built upon:
- Prometheus - metrics
- Loki - logging
  - Promtail - log delivery
- Opencost - cost accounting
- Grafana - visualization
- Alertmanager - alerting

## Installation
Note: The stack is configured to use Keycloak for SSO; therefore, the ref-implementation is required for this to work. 

`idpbuilder create --use-path-routing --package-dir ./ref-implementation --package-dir ./observability`

A `grafana-config` job will be deployed into the keycloak namespace to create/patch some of the keycloak components. If deployed at the same time as the `ref-implementation`, this job will fail until the `config` job succeeds. This is normal
