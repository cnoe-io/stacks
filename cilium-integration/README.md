# Cilium Integration

`idpBuilder` is extensible to launch custom Crossplane patterns using package extensions. This stack contains the code for integrating Cilium with IDPBuilder.

```bash
idpbuilder create --package https://github.com/cnoe-io/stacks//cilium-integration
```

## What is installed?

1. Cilium
2. Hubble UI
3. Tetragon

Navigating to https://hubble.cnoe.localtest.me:8443/ will bring you to the Hubble UI where you can visualize the network traffic in the cluster.

You can also run `kubectl logs -lapp.kubernetes.io/name=tetragon -n kube-system` to see processes running inside of the pods running from Tetragon. 