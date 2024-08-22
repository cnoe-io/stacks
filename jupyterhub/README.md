# Jupyterhub Stack

This directory contains a Jupyterhub deployment that's integrated with Keycloak

## Caveats
1) Reliance on `ref-implementation` for SSO
    - This is possible to work around by setting `authenticator_class` in the `jupyterhub.yaml` to `dummy`.

## Components
- Jupyterhub

## Installation
Note: The stack is configured to use Keycloak for SSO; therefore, the ref-implementation is required for this to work.

`idpbuilder create --use-path-routing  -p https://github.com/cnoe-io/stacks//ref-implementation -p https://github.com/cnoe-io/stacks//jupyterhub`

A `jupyterhub-config` job will be deployed into the keycloak namespace to create/patch some of the keycloak components. If deployed at the same time as the `ref-implementation`, this job will fail until the `config` job succeeds. This is normal
