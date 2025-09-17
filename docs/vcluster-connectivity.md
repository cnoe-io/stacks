# VCluster Connectivity (Linux)

This guide covers how to generate local kubeconfigs for the dev and staging vclusters when running on a native Linux workstation. The helper script avoids all WSL-specific overrides and produces simple context names that mirror the stage names.

## Prerequisites

- A Kind-based host cluster created with the platform tooling (`deploy-linux-ssh.sh` or `cluster-deploy`).
- The `kubectl` and `vcluster` CLIs available in your `$PATH`.
- VCluster workloads have been synced by ArgoCD (pods `vcluster-dev-helm-0` and `vcluster-staging-helm-0`).

## Generate kubeconfigs

Run the consolidated helper:

```bash
bash ref-implementation/setup-vcluster-kubeconfigs.sh
```

What it does:

- Waits for each vcluster pod to report `Running` status.
- Reads the `vc-vcluster-<stage>-helm` secret to capture the CA, client certificate, and client key.
- Backs up your existing kubeconfig, updates it in-place, and leaves everything in `~/.kube/config`.
- Creates stage contexts named `dev` and `staging` alongside your host cluster.

Environment variables:

- `VCLUSTER_BASE_DOMAIN` – defaults to `cnoe.localtest.me`. Override if you expose the ingress at another host.
- `VCLUSTER_TLS_PORT` – defaults to `8443`. Override when the ingress terminates TLS on a different port.

## Verify access

```bash
kubectl config get-contexts
kubectl --context dev get ns
kubectl --context staging get ns
```

If verification fails, re-run the script or check the pod status:

```bash
kubectl get pods -n dev-vcluster
kubectl get pods -n staging-vcluster
```

## Resetting

A backup of your old kubeconfig is written as `~/.kube/config.bak.<timestamp>`. To revert:

```bash
cp ~/.kube/config.bak.<timestamp> ~/.kube/config
```

Re-run the setup script after recreating the cluster to refresh certificates and contexts.
