# Plan to Remove `idpbuilder` Dependency

This document details the complete background analysis and step-by-step implementation plan for removing the `idpbuilder` dependency from the `stacks` Kubernetes setup and cluster management scripts. The goal is to fully transition to native tools (Kind, Helm, and GitOps) while maintaining the exact same local developer experience.

## Background Analysis

`idpbuilder` is a tool that provisions an Internal Developer Platform on top of a Kubernetes cluster (usually `kind`). Currently, the `stacks` project relies on `idpbuilder` for several critical abstractions:

### 1. Cluster Provisioning and CoreDNS Modification
When `idpbuilder create` is run, it provisions a Kind cluster and injects a custom CoreDNS `ConfigMap` (`coredns-conf-default`) into the `kube-system` namespace.
This custom configuration allows any subdomains of `cnoe.localtest.me` (like `gitea.cnoe.localtest.me` or `argocd.cnoe.localtest.me`) to resolve internally to the IP address of the `ingress-nginx-controller`. This is crucial for local GitOps, as ArgoCD needs to resolve the local Gitea instance correctly.

### 2. Base Components Installation (NGINX, Gitea, ArgoCD)
`idpbuilder` embeds and automatically installs base infrastructural components using standard manifests and Helm charts:
*   **ingress-nginx**: Deployed to expose services.
*   **gitea**: A local Git server used to host manifest repositories. It exposes port 8443 and creates a default admin user.
*   **argo-cd**: The GitOps engine. `idpbuilder` installs it and sets up a `GitRepository` Custom Resource and a `Localbuild` Custom Resource to wire ArgoCD to Gitea.

### 3. The `cnoe://` Protocol Abstraction
This is the most significant abstraction. In `packages/base/apps/*.yaml`, the `repoURL` is set to `cnoe://<package>/manifests`.
When `idpbuilder` detects the `cnoe://` protocol in an ArgoCD Application, its internal controllers (`custompackage` and `localbuild` controllers) do the following:
*   It intercepts the local manifests from the directories specified via the `-p` flag (`dist/$KUSTOMIZE_BUILD_ENV/`).
*   It creates a repository in the internal Gitea instance for each package or a consolidated one.
*   It pushes the local manifest files into this Gitea repository.
*   It dynamically mutates the ArgoCD `Application` resource in the cluster, changing the `repoURL` from `cnoe://...` to the internal Gitea HTTP URL (`https://gitea.cnoe.localtest.me:8443/...`).
This mechanism allows developers to edit local files, run `idpbuilder create`, and have their changes immediately synced to ArgoCD without needing to manually commit and push to a remote Git repository.

---

## Step-by-Step Implementation Plan

To eliminate `idpbuilder`, we must replicate the above capabilities using standard scripts and Kubernetes resources. 

### Phase 1: Cluster Creation and Networking
1.  **Replace `idpbuilder create` with Native `kind`**:
    *   In `deployment/scripts/cluster-menu.sh` (`cluster-apply-manifests` and `cluster-deploy`), change the cluster creation command to `kind create cluster --name "$CLUSTER_NAME" --config "$DEPLOY_DIR/config/kind-config.yaml"`.
2.  **Patch CoreDNS**:
    *   Create a script or manifest (e.g., `deployment/config/coredns-patch.yaml`) that configures the `kube-system` `coredns` ConfigMap.
    *   Inject the rewrite rules:
        ```text
        rewrite stop {
            name regex (.*).cnoe.localtest.me ingress-nginx-controller.ingress-nginx.svc.cluster.local answer auto
        }
        rewrite name exact cnoe.localtest.me ingress-nginx-controller.ingress-nginx.svc.cluster.local
        ```
    *   Apply this patch immediately after the `kind` cluster is created.

### Phase 2: Bootstrap Base Components
Since `idpbuilder` will no longer install NGINX, Gitea, and ArgoCD, we will script their installation.
1.  **Create `scripts/bootstrap-kind-core.sh`**:
    *   **NGINX Ingress**: Apply the NGINX ingress controller manifests (e.g., via `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml`).
    *   **Gitea**: Install Gitea via Helm. We need to create a `values.yaml` that mirrors what `idpbuilder` uses, specifically setting the admin credentials to `giteaadmin` and exposing it properly over the ingress.
    *   **ArgoCD**: Adapt the existing `scripts/01-install-argocd.sh` to ensure it works for the `kind` cluster setup and applies the TLS overrides if necessary.

### Phase 3: Replace the `cnoe://` Protocol with Native Local GitOps
We will use a standard Git syncing approach to push local development manifests to the internal Gitea instance.
1.  **Create `deployment/scripts/sync-local-manifests.sh`**:
    *   This script will be invoked during `cluster-update` and `cluster-deploy` after `cluster-build` completes.
    *   It will navigate to `packages/dist/$KUSTOMIZE_BUILD_ENV/`.
    *   It will initialize a temporary Git repository (`git init`).
    *   It will add and commit all files.
    *   It will force-push the repository to the internal Gitea instance: 
        `git push -f https://giteaadmin:$PASSWORD@gitea.cnoe.localtest.me:8443/giteaadmin/local-manifests.git HEAD:main`
2.  **Update ArgoCD Applications**:
    *   Iterate through all Application manifests in `packages/base/apps/*.yaml`.
    *   Change the `repoURL` from `cnoe://<app>/manifests` to the new standard Gitea URL: `https://gitea.cnoe.localtest.me:8443/giteaadmin/local-manifests.git`.
    *   Change the `path` directive to point to the specific application's subfolder: `path: "<app>/manifests"`.
    *   Update the `kargo` pipelines similarly if they rely on the `cnoe://` protocol.

### Phase 4: Refactor `cluster-menu.sh` Workflows
Update the core operational functions in `deployment/scripts/cluster-menu.sh` to use the new native workflow.
1.  **Refactor `cluster-apply-manifests` / `cluster-deploy`**:
    *   Run `kind create cluster`.
    *   Apply the CoreDNS patch.
    *   Run `bootstrap-kind-core.sh` to install NGINX, Gitea, ArgoCD.
    *   Wait for Gitea to be healthy and create the `local-manifests` repository via API if it doesn't exist.
    *   Run `kustomize-build` to generate the local manifests.
    *   Run `sync-local-manifests.sh` to push the generated manifests to the internal Gitea.
    *   Apply the ArgoCD `Application` CRs from `packages/dist/$KUSTOMIZE_BUILD_ENV/` so ArgoCD starts managing them.
2.  **Refactor `cluster-update`**:
    *   Run `kustomize-build`.
    *   Run `sync-local-manifests.sh` to push updates to internal Gitea.
    *   ArgoCD will automatically detect the Git changes and sync, maintaining the fast inner-loop experience.
3.  **Refactor `cluster-recreate`**:
    *   Replace `idpbuilder delete` with standard `kind delete cluster --name "$CLUSTER_NAME"`.

### Phase 5: Verification and Cleanup
1.  **Testing**:
    *   Run `clr` to delete the existing cluster.
    *   Run `cld` to provision the new cluster and verify that all ArgoCD apps sync successfully.
    *   Make a local change to a manifest, run `clu`, and verify ArgoCD updates the resource automatically.
2.  **Cleanup**:
    *   Remove all `idpbuilder`-specific flags, overrides, and cleanup logic (e.g., stale custom package cleanup) from the scripts.
    *   Remove `idpbuilder` from installation guides and prerequisites documentation.
