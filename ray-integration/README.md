# Ray Integrations

`idpBuilder` is extensible to install Ray Operator for Serving machine learning (ML) models at scale. This integration will help us Ray Kubernetes Operator integrated into our platform which simplifies and accelerates the serving of ML models.

Please use the following command to deploy ray using `idpbuilder`:

```bash
idpbuilder create \
  --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ray-integration
```

Notice that you can add Ray to the reference implementation:

```bash
idpbuilder create \
  --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation \
  -p https://github.com/cnoe-io/stacks//ray-integration
```

## What is installed?

1. Ray Operator CRDs
2. Ray Operator

Once installed, you will have Ray Operator and Ray Serve components to serve the ML model and LLMs.

For more information, check our module [here](https://catalog.us-east-1.prod.workshops.aws/modernengg/en-US/60-aimldelivery/63-section4-ml-model-use-case) for a step by step instructions on Serving ML Models via Internal Developer Platforms with an example. 


