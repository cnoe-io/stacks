# VCluster Connection Guide

## Overview
This guide explains how to connect to the dev and staging vclusters from a native Linux environment. The workflow relies on the shared helper `ref-implementation/setup-vcluster-kubeconfigs.sh`, which assembles kubeconfigs with straightforward stage names and no localhost overrides.

## Steps

### 1. Generate/refresh kubeconfigs
From the repository root:

```bash
bash ref-implementation/setup-vcluster-kubeconfigs.sh
```

The script:
- Waits for the Helm-managed vcluster pods to report `Running`.
- Extracts TLS material from the `vc-vcluster-<stage>-helm` secret.
- Backs up your kubeconfig and injects the stage contexts (`dev`, `staging`) directly into `~/.kube/config`.

### 2. Switch contexts

```bash
kubectl config use-context dev
kubectl get ns

kubectl config use-context staging
kubectl get ns
```

Each context targets the ingress endpoint `https://<stage>-vcluster.cnoe.localtest.me:8443` by default. Override the domain or port by exporting `VCLUSTER_BASE_DOMAIN` or `VCLUSTER_TLS_PORT` before running the setup script.

### 3. Troubleshooting

- **Context missing**: Re-run the setup script after the vcluster pods are healthy (`kubectl get pods -n dev-vcluster`).
- **Certificate errors**: Verify that the ingress host resolves locally (`nslookup dev-vcluster.cnoe.localtest.me`).
- **Need to roll back**: Restore `~/.kube/config` from the timestamped `.bak` file created by the script.

## Quick reference

```bash
# Refresh contexts
bash ref-implementation/setup-vcluster-kubeconfigs.sh

# List contexts
kubectl config get-contexts | grep -E '(dev|staging|kind)'

# Validate connectivity
kubectl --context dev get nodes
kubectl --context staging get nodes
```

No additional port forwarding or kubeconfig editing is necessary on Linux.
