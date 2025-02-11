# Dapr Integrations 

`idpBuilder` is extensible to launch custom Dapr patterns using package extensions. 

Please use the following command to deploy Dapr using `idpbuilder`:

```bash
idpbuilder create \
  --use-path-routing \
  -p https://github.com/cnoe-io/stacks//dapr-integrations \
```

Notice that you can add Dapr to the reference implementation:

```bash
idpbuilder create \
  --use-path-routing \
  -p https://github.com/cnoe-io/stacks//ref-implementation \
  -p https://github.com/cnoe-io/stacks//dapr-integrations
```

## What is installed?

1. Dapr Control Plane
1. Dapr Statestore and PubSub components
2. Redis instance to support Statestore and Pubsub components

Once installed, you can enable your workloads (Deployments) to use the Dapr APIs by using the Dapr annotations:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodeapp
  labels:
    app: node
spec:
  replicas: 1
  selector:
    matchLabels:
      app: node
  template:
    metadata:
      labels:
        app: node
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "nodeapp"
        dapr.io/app-port: "3000"
        dapr.io/enable-api-logging: "true"
    spec:
      containers:
      - name: node
        image: ghcr.io/dapr/samples/hello-k8s-node:latest
        env:
        - name: APP_PORT
          value: "3000"
        ports:
        - containerPort: 3000
        imagePullPolicy: Always
```
This example creates a Dapr-enabled Kubernetes Deployment (setting the `dapr.io/*` annotations). This application can now use the Dapr APIs to interact with the Statestore and PubSub components provided by the default installation. Applications can be written in any programming language, check the [Dapr SDKs here](https://docs.dapr.io/developing-applications/sdks/).

For more information, check the Hello Kubernetes Dapr tutorial [here](https://github.com/dapr/quickstarts/tree/master/tutorials/hello-kubernetes)


