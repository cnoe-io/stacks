# Dapr Integrations 

`idpBuilder` is extensible to launch custom Dapr patterns using package extensions. 

Please use the below command to deploy an IDP reference implementation with an Argo application for preparing up the setup for terraform integrations:

```bash
idpbuilder create \
  --use-path-routing \
  --p https://github.com/cnoe-io/stacks//dapr-integrations
```
## What is installed?

1. Dapr Control Plane
1. Dapr Statestore and PubSub components
2. Redis instance to support Statestore and Pubsub components



