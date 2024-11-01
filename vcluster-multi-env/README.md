# IDP Builder Multi-Environment

Multi-environment emulation on top of CNOE.

# Configuring Clusters

By default, this stack creates two vclusters (staging and production). If you
desire a different configuration you can edit the following list in
`vclusters.yaml`:

```yaml
  generators:
  - list:
      elements:
      - name: staging
      - name: production
```

# Running

```bash
# Create CNOE deployment with vcluster-multi-env stack
idpbuilder create -p vcluster-multi-env

# Enroll vclusters in ArgoCD
./vcluster-multi-env/add-vclusters.sh
```

# Using

Your CNOE ArgoCD should now have a cluster enrolled for each configured
vcluster (staging and production by default). These clusters will have the
following labels for your use:

```yaml
    cnoe.io/vclusterMultiEnv/clusterClass: "app-runtime"
    cnoe.io/vclusterMultiEnv/clusterName: "${cluster_name}"
```

You may now target them using, for example, an ArgoCD ApplicationSet cluster
generator which matches these labels.
